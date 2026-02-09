import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/image_view.dart';
import 'package:doppy/pages/components/post_action_bottom_sheet.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/profile_feed_sections_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/data/models/access_level.dart';
import 'package:doppy/pages/components/access_level_sheet.dart'
    show AccessLevelSheet, AccessLevelSelectMode;

/// 그리드 버전 포스트 섹션 - 3개씩 여러 줄로 표시
class GridCategorySection extends StatefulWidget {
  const GridCategorySection({
    super.key,
    required this.posts,
    required this.displayMode,
    required this.isLastSection,
    required this.mainScrollController,
    this.isOwnProfile = true,
  });

  final List<PostData> posts;
  final dynamic displayMode;
  final bool isLastSection;
  final ScrollController? mainScrollController;
  final bool isOwnProfile;

  @override
  State<GridCategorySection> createState() => _GridCategorySectionState();
}

class _GridCategorySectionState extends State<GridCategorySection> {
  int? _postDropTargetIndex;
  int? _draggingPostIndex;

  BaseFeedProvider? _readFeedProvider(BuildContext context) {
    // ✅ 어떤 트리에서도 크래시 없이 동작하도록 폴백 제공
    try {
      return context.read<BaseFeedProvider>();
    } catch (_) {}
    try {
      return context.read<MyProfileFeedProvider>();
    } catch (_) {}
    try {
      return context.read<OtherProfileFeedProvider>();
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feedProvider = _readFeedProvider(context);
    final isReadOnly = feedProvider?.isReadOnly ?? true;

    if (widget.posts.isEmpty) {
      return widget.isLastSection
          ? const SizedBox(height: 20)
          : const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: ValueNotifier<bool>(false), // 카테고리 드래그 제거
      builder: (context, isDragging, _) {
        final screenWidth = MediaQuery.of(context).size.width;
        final cardWidth = screenWidth / 3;

        return Opacity(
          opacity: isDragging ? 0.3 : 1.0,
          child: DragTarget<PostData>(
            onWillAccept: (_) => !isReadOnly,
            onMove: (details) {
              setState(() => _postDropTargetIndex = widget.posts.length);
            },
            onLeave: (_) {
              setState(() => _postDropTargetIndex = null);
            },
            onAccept: (draggedPost) async {
              if (widget.posts.contains(draggedPost)) {
                final draggedIndex = widget.posts.indexOf(draggedPost);
                final targetIndex = widget.posts.length - 1; // 마지막 포스트와 스왑

                if (draggedIndex != targetIndex) {
                  // ✅ 마지막 포스트와 드래그된 포스트를 스왑
                  await _swapPostsWithServer(
                    context,
                    draggedPost.id,
                    draggedIndex,
                    targetIndex,
                  );
                }
              }
              setState(() => _postDropTargetIndex = null);
            },
            builder: (context, candidateData, rejectedData) {
              final bool hasCandidate = candidateData.isNotEmpty;
              final bool isLastTarget =
                  !isReadOnly &&
                  hasCandidate &&
                  _postDropTargetIndex == widget.posts.length &&
                  _draggingPostIndex != widget.posts.length - 1;

              return ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2.5,
                    crossAxisSpacing: 2,
                    childAspectRatio: 4 / 5,
                  ),
                  itemCount: widget.posts.length,
                  itemBuilder: (context, index) {
                    // 마지막 아이템이고 타겟 위치일 때 흐려지게
                    final bool isLastItem = index == widget.posts.length - 1;
                    final double itemOpacity =
                        isLastItem && isLastTarget ? 0.4 : 1.0;

                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      opacity: itemOpacity,
                      child: _buildGridItem(
                        context,
                        theme,
                        widget.posts[index],
                        index,
                        cardWidth,
                        isReadOnly,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGridItem(
    BuildContext context,
    ThemeData theme,
    PostData post,
    int index,
    double cardWidth,
    bool isReadOnly,
  ) {
    if (isReadOnly) {
      return SizedBox(
        width: cardWidth,
        child: GestureDetector(
          onTap: () => _openPost(context, post, index),
          onLongPress: () {
            PostActionBottomSheet.show(
              context,
              postId: post.id,
              postTitle: post.title,
              authorUsername: post.author,
              authorProfileImageUrl: post.authorProfileImageUrl,
              thumbnailImageUrl: post.thumbnailImageUrl,
              likeCount: post.likeCount,
              hideProfileOption: true, // 프로필 화면에서 호출되므로 프로필 방문 옵션 숨김
            );
          },
          child: ImageView(
            key: ValueKey('image-${post.id}'),
            post: post,
            isFirst: false,
            isLast: false,
            showViewCount: !isReadOnly,
          ),
        ),
      );
    }

    return DragTarget<PostData>(
      onWillAccept: (data) => true,
      onMove: (details) {
        setState(() {
          _postDropTargetIndex = index;
        });
      },
      onLeave: (_) {
        setState(() => _postDropTargetIndex = null);
      },
      onAccept: (draggedPost) async {
        final draggedIndex = widget.posts.indexOf(draggedPost);
        final targetIndex = _postDropTargetIndex ?? index;

        if (draggedIndex != -1) {
          if (draggedIndex == targetIndex) {
            setState(() => _postDropTargetIndex = null);
            return;
          }
          // ✅ 투명해진 포스트(타겟)와 드래그된 포스트를 스왑
          await _swapPostsWithServer(
            context,
            draggedPost.id,
            draggedIndex,
            targetIndex,
          );
        }
        setState(() => _postDropTargetIndex = null);
      },
      builder: (context, candidateData, rejectedData) {
        final bool hasCandidate = candidateData.isNotEmpty;
        final bool isTargeted = _postDropTargetIndex == index;
        final bool isDragging = _draggingPostIndex == index;

        // 타겟 위치의 포스트는 흐려지게 표시 (드래그 중인 포스트 제외)
        final double targetOpacity =
            hasCandidate && isTargeted && !isDragging ? 0.4 : 1.0;

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          opacity: targetOpacity,
          child: SizedBox(
            width: cardWidth,
            child: LongPressDraggable<PostData>(
              data: post,
              dragAnchorStrategy: (draggable, context, position) {
                return Offset(cardWidth * 0.9 / 2 + 10, 200.0 * 0.9 / 2 + 20);
              },
              onDragStarted: () {
                setState(() => _draggingPostIndex = index);
              },
              onDragUpdate: (details) {
                final sc = widget.mainScrollController;
                if (sc != null && sc.hasClients) {
                  final screenHeight = MediaQuery.of(context).size.height;
                  final globalY = details.globalPosition.dy;
                  const edge = 100.0;
                  const speed = 14.0;
                  final pos = sc.position;
                  if (globalY < edge) {
                    final next = (pos.pixels - speed).clamp(
                      0.0,
                      pos.maxScrollExtent,
                    );
                    if (next != pos.pixels) sc.jumpTo(next);
                  } else if (globalY > screenHeight - edge) {
                    final next = (pos.pixels + speed).clamp(
                      0.0,
                      pos.maxScrollExtent,
                    );
                    if (next != pos.pixels) sc.jumpTo(next);
                  }
                }
              },
              onDragEnd: (_) {
                setState(() {
                  _postDropTargetIndex = null;
                  _draggingPostIndex = null;
                });
              },
              feedback: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.94, end: 1.0),
                duration: const Duration(
                  milliseconds: 700,
                ), // 🎯 더 느리게 "쑥" 뽑히는 느낌
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Opacity(
                  opacity: 0.85,
                  child: Material(
                    elevation: 10,
                    type: MaterialType.transparency,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: cardWidth,
                      child: ImageView(
                        key: ValueKey('image-${post.id}'),
                        post: post,
                        isFirst: false,
                        isLast: false,
                        showViewCount: !isReadOnly,
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: ImageView(
                  key: ValueKey('image-${post.id}'),
                  post: post,
                  isFirst: false,
                  isLast: false,
                  showViewCount: !isReadOnly,
                ),
              ),
              child: GestureDetector(
                onTap: () => _openPost(context, post, index),
                child: ImageView(
                  key: ValueKey('image-${post.id}'),
                  post: post,
                  isFirst: false,
                  isLast: false,
                  showViewCount: !isReadOnly,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPost(BuildContext context, PostData post, int index) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PostReaderScreen(
              exported: post.toExportedData(),
              heroTag: 'profile-post-${post.id}',
              fromProfile: true,
            ),
      ),
    );

    if (result != null) {
      if (result['deleted'] == true) {
        // ✅ 포스트 삭제 시 "전체 & 모든 포스트 모드"로 재로드
        try {
          final sectionsProvider = context.read<ProfileFeedSectionsProvider>();
          final userProvider = context.read<UserProvider>();
          final currentUser = userProvider.currentUser;
          final username = currentUser?.username;

          if (username != null && username.isNotEmpty) {
            await sectionsProvider.loadSections(
              username: username,
              force: true,
            );
            debugPrint(
              '[GridCategorySection] ✅ 포스트 삭제 후 sections 재로드 완료 (전체 모드)',
            );
          }
        } catch (e) {
          debugPrint('[GridCategorySection] ⚠️ sections 재로드 실패: $e');
          // 폴백: 기존 방식으로 피드만 새로고침
          final provider = _readFeedProvider(context);
          if (provider != null) {
            provider.clearInMemory();
            provider.setNetworkError(null);
            await provider.loadInitial(force: true);
          }
        }
      } else if (result['accessLevelChanged'] == true) {
        final postId = result['postId']?.toString();
        final accessLevel = result['accessLevel']?.toString();

        if (postId != null && accessLevel != null) {
          final provider = _readFeedProvider(context);
          if (provider == null) return;
          provider.updatePostMetadata(postId, accessLevel: accessLevel);
        } else {
          final provider = _readFeedProvider(context);
          if (provider == null) return;
          provider.clearInMemory();
          provider.setNetworkError(null);
          await provider.loadInitial(force: true);
        }
      } else if (result['didEdit'] == true) {
        // ✅ 포스트 수정 시 "전체 & 모든 포스트 모드"로 재로드
        try {
          final sectionsProvider = context.read<ProfileFeedSectionsProvider>();
          final userProvider = context.read<UserProvider>();
          final currentUser = userProvider.currentUser;
          final username = currentUser?.username;

          if (username != null && username.isNotEmpty) {
            await sectionsProvider.loadSections(
              username: username,
              force: true,
            );
            debugPrint(
              '[GridCategorySection] ✅ 포스트 수정 후 sections 재로드 완료 (전체 모드)',
            );
          }
        } catch (e) {
          debugPrint('[GridCategorySection] ⚠️ sections 재로드 실패: $e');
          // 폴백: 기존 방식으로 피드만 새로고침
          final provider = _readFeedProvider(context);
          if (provider != null) {
            provider.clearInMemory();
            provider.setNetworkError(null);
            await provider.loadInitial(force: true);
          }
        }
      }
    }
  }

  /// ✅ 투명해진 포스트(타겟)와 드래그된 포스트를 스왑
  Future<void> _swapPostsWithServer(
    BuildContext context,
    String draggedPostId,
    int draggedIndex,
    int targetIndex,
  ) async {
    try {
      final provider = _readFeedProvider(context);
      if (provider == null) return;

      if (provider is MyProfileFeedProvider) {
        // 로컬에서 먼저 순서 변경 (스왑)
        final allPosts = provider.posts;

        // 드래그된 포스트와 타겟 포스트의 인덱스 찾기
        final draggedPostIndex = allPosts.indexWhere(
          (p) => '${p['id']}' == draggedPostId,
        );

        if (draggedPostIndex == -1) return;

        // 타겟 포스트는 widget.posts의 인덱스를 사용하여 전체 리스트에서 찾기
        // widget.posts는 현재 섹션의 포스트만 포함하므로, 전체 리스트에서 해당 포스트 찾기
        final targetPost = widget.posts[targetIndex];
        final targetPostId = targetPost.id;
        final targetPostIndex = allPosts.indexWhere(
          (p) => '${p['id']}' == targetPostId,
        );

        if (targetPostIndex == -1) return;

        // 같은 인덱스면 스왑 불필요
        if (draggedPostIndex == targetPostIndex) return;

        // 스왑: 두 포스트의 위치를 바꿈
        final newPosts = List<Map<String, dynamic>>.from(allPosts);
        final draggedPost = newPosts[draggedPostIndex];
        final targetPostData = newPosts[targetPostIndex];

        newPosts[draggedPostIndex] = targetPostData;
        newPosts[targetPostIndex] = draggedPost;

        // 전체 포스트 ID 배열 생성
        final orderedPostIds = newPosts.map((post) => '${post['id']}').toList();

        // 서버에 순서 변경 요청
        await provider.reorderPosts(orderedPostIds);
      }
    } catch (e) {
      debugPrint('⚠️ [GridCategorySection] 포스트 스왑 서버 저장 실패: $e');
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('포스트 순서 저장에 실패했습니다')));
      } catch (_) {}
    }
  }

  Future<void> _deletePost(BuildContext context, PostData post) async {
    final l10n = AppLocalizations.of(context);

    final bool? shouldDelete = await DialogUtils.showConfirmDialog(
      context,
      title: l10n.translate('delete_post_confirm_title'),
      message: l10n.translate('delete_post_confirm_message'),
      confirmText: l10n.translate('delete'),
      cancelText: l10n.translate('cancel'),
      isDestructive: true,
    );

    if (shouldDelete != true) return;

    try {
      final blogService = BlogService();
      final provider = _readFeedProvider(context);
      if (provider == null) return;

      await blogService.deletePost(post.id);

      // ✅ 포스트 삭제 시 "전체 & 모든 포스트 모드"로 재로드
      try {
        final sectionsProvider = context.read<ProfileFeedSectionsProvider>();
        final userProvider = context.read<UserProvider>();
        final currentUser = userProvider.currentUser;
        final username = currentUser?.username;

        if (username != null && username.isNotEmpty) {
          await sectionsProvider.loadSections(username: username, force: true);
          debugPrint(
            '[GridCategorySection] ✅ 포스트 삭제 후 sections 재로드 완료 (전체 모드)',
          );
        }
      } catch (e) {
        debugPrint('[GridCategorySection] ⚠️ sections 재로드 실패: $e');
        // 폴백: 기존 방식으로 피드만 새로고침
        provider.clearInMemory();
        provider.setNetworkError(null);
        await provider.loadInitial(force: true);
      }

      if (context.mounted) {
        ErrorHandler.showInfo(context, l10n.translate('post_deleted'));
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(context, l10n.translate('post_delete_failed'));
      }
    }
  }

  Future<void> _changePostAccessLevel(
    BuildContext context,
    PostData post,
  ) async {
    final provider = _readFeedProvider(context);
    if (provider == null) return;

    // 🎯 새로운 AccessLevel enum의 serverValue 사용
    final currentAccessLevel = post.accessLevel.serverValue;

    AccessLevelSheet.show(
      context,
      postId: post.id,
      currentAccessLevel: currentAccessLevel,
      mode: AccessLevelSelectMode.serverUpdate,
      onChanged: (String accessLevel) async {
        provider.updatePostMetadata(post.id, accessLevel: accessLevel);
      },
    );
  }
}
