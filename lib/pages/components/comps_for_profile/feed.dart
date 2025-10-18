import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/common/reorderable_grid_list.dart';
import 'package:doppy/pages/components/comps_for_profile/card_mode_list.dart';

// ===== Category row reorder helpers (aligned with editor DragService) =====
bool _shouldShowDropLine({
  required int currentIndex,
  required int? draggingIndex,
  required int? dropTargetIndex,
}) {
  if (dropTargetIndex != currentIndex) return false;
  if (draggingIndex == null) return false;
  // Hide on self and immediate below (adjacent scheme), like editor
  if (currentIndex == draggingIndex) return false;
  if (currentIndex == draggingIndex + 1) return false;
  return true;
}

bool _shouldShowBottomLine({
  required int sectionsLength,
  required int? draggingIndex,
  required int? dropTargetIndex,
}) {
  if (dropTargetIndex != sectionsLength) return false;
  if (draggingIndex == null) return false;
  // If dragging the last item, bottom line is adjacent → hide
  if (draggingIndex == sectionsLength - 1) return false;
  return true;
}

// 카테고리 섹션 메타 (파일 최상위)
class _FeedSectionMeta {
  const _FeedSectionMeta({
    required this.title,
    required this.posts,
    this.categoryId,
  });
  final String title;
  final List<PostData> posts;
  final String? categoryId;
}

class Feed {
  // 카테고리 드래그 상태 관리
  final ValueNotifier<bool> _isDraggingCategory = ValueNotifier(false);
  final ValueNotifier<int?> _categoryDropTargetIndex = ValueNotifier(null);
  final ValueNotifier<int?> _draggingSectionIndex = ValueNotifier(null);
  ScrollController? _mainScrollController;

  // 외부에서 드래그 상태 접근 가능하도록 getter 추가
  ValueNotifier<bool> get isDraggingCategory => _isDraggingCategory;

  // 드래그 상태 변경 콜백
  VoidCallback? onDragStateChanged;

  bool _stringListEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 시스템 카테고리인지 확인
  bool _isSystemCategory(String categoryName) {
    return categoryName == '전체공개' ||
        categoryName == '나만보기' ||
        categoryName == '그룹공유';
  }

  /// BaseFilter를 시스템 카테고리 ID로 변환
  String? _getSystemCategoryId(BaseFilter base) {
    switch (base) {
      case BaseFilter.public:
        return '-1';
      case BaseFilter.private:
        return '-2';
      case BaseFilter.groups:
        return '-3';
      case BaseFilter.all:
        return null;
    }
  }

  /// 카테고리 제목 변환 (system_doppy_uncategorized -> {username}의 다른 글)
  String _getCategoryDisplayTitle(
    String title,
    String categoryId,
    String? username,
  ) {
    if (categoryId == '0') {
      return username != null && username.isNotEmpty
          ? '$username의 다른 글'
          : '다른 글';
    }
    return title;
  }

  Widget buildFeedContent({ScrollController? scrollController}) {
    _mainScrollController = scrollController;
    return ValueListenableBuilder<FeedDisplayMode>(
      valueListenable: FeedDisplayModeManager(),
      builder: (context, displayMode, _) {
        return Consumer<ProfileFeedProvider>(
          builder: (context, feedProvider, _) {
            final postsRaw = feedProvider.posts;
            // 디버깅 로그: 현재 상태 요약
            // ignore: avoid_print
            print(
              '[Feed] isLoading=${feedProvider.isLoading} postsRaw=${postsRaw.length} cats=${feedProvider.categories.length} selId=${feedProvider.selectedCategoryId} selBase=${feedProvider.selectedBase}',
            );

            // 로딩 중이고 포스트가 비어있으면 아무것도 표시하지 않음
            if (feedProvider.isLoading && postsRaw.isEmpty) {
              // ignore: avoid_print
              print('[Feed] 로딩중 + 포스트 비어있음 → 아무것도 표시 안 함');
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            // 로딩 완료 후 포스트가 비어있는 경우에만 메시지 표시
            if (postsRaw.isEmpty) {
              // ignore: avoid_print
              print('[Feed] 포스트 비어있음 (로딩 완료) → 비어있는 안내 UI 표시');

              // 포스트가 없더라도 카테고리가 있으면 빈 섹션 헤더를 표시
              final hasCategories = (feedProvider.categories.isNotEmpty);
              if (hasCategories) {
                final sections = <_FeedSectionMeta>[
                  for (final cat in feedProvider.categories)
                    _FeedSectionMeta(
                      title: cat['name'],
                      posts: const [],
                      categoryId: cat['id'].toString(),
                    ),
                ];
                // 섹션 헤더만 렌더링(빈 가로 리스트)
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final sec = sections[index];
                    return _buildHorizontalSection(
                      context,
                      sec,
                      displayMode,
                      index,
                    );
                  }, childCount: sections.length),
                );
              }

              // 빈 메시지 표시 (로딩 완료 후에만)
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 40,
                  ),
                  child: Center(
                    child: Text(
                      '아직은 포스트가 없어요!',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
              );
            }

            // 1) 서버 포스트를 PostData로 안전 변환
            final allPosts = <PostData>[];
            for (final raw in postsRaw) {
              try {
                allPosts.add(PostData.fromServer(raw));
              } catch (_) {}
            }

            // 2) 카테고리 기반 그룹핑 (사용자가 만든 카테고리만) + 선택 필터 반영
            final hasCategories = (feedProvider.categories.isNotEmpty);

            // 활성 필터 확인: 사용자 카테고리 선택 또는 기본 탭 선택
            final bool hasSelection =
                (feedProvider.selectedCategoryId != null) ||
                (feedProvider.selectedBase != BaseFilter.all);
            print(
              '[Feed] hasSelection: $hasSelection, selectedCategoryId: ${feedProvider.selectedCategoryId}, selectedBase: ${feedProvider.selectedBase}',
            );

            if (hasSelection) {
              // 단일 그리드로 필터 결과 표시
              final isReadOnly = feedProvider.isReadOnly;
              final List<PostData> filtered;
              if (feedProvider.selectedCategoryId != null) {
                final String selId = feedProvider.selectedCategoryId!;

                // 시스템 카테고리 ID인지 확인 (-1, -2, -3)
                if (selId == '-1' || selId == '-2' || selId == '-3') {
                  // 시스템 카테고리의 포스트들 가져오기
                  final systemPosts = feedProvider.postsByCategory[selId] ?? [];
                  filtered =
                      systemPosts
                          .map((raw) {
                            try {
                              return PostData.fromServer(raw);
                            } catch (_) {
                              return null;
                            }
                          })
                          .where((p) => p != null)
                          .cast<PostData>()
                          .toList();
                } else {
                  // 사용자가 만든 카테고리
                  final cat = feedProvider.categories.firstWhere(
                    (c) => c['id'].toString() == selId,
                    orElse: () => {'id': '', 'name': ''},
                  );
                  if (cat['id'].toString().isEmpty) {
                    filtered = const <PostData>[];
                  } else {
                    // 사용자 카테고리의 경우 해당 카테고리의 포스트들을 가져오기
                    final categoryPosts =
                        feedProvider.postsByCategory[selId] ?? [];
                    filtered =
                        categoryPosts
                            .map((raw) {
                              try {
                                return PostData.fromServer(raw);
                              } catch (_) {
                                return null;
                              }
                            })
                            .where((p) => p != null)
                            .cast<PostData>()
                            .toList();
                  }
                }
              } else {
                // 시스템 카테고리 필터 (전체/나만보기/그룹공유/전체공개)
                final base = feedProvider.selectedBase;
                final isReadOnly = feedProvider.isReadOnly;

                // ProfileFeedProvider에서 시스템 카테고리 데이터 가져오기
                final systemCategoryId = _getSystemCategoryId(base);
                if (systemCategoryId != null) {
                  // 시스템 카테고리의 포스트들 가져오기
                  final systemPosts =
                      feedProvider.postsByCategory[systemCategoryId] ?? [];
                  filtered =
                      systemPosts
                          .map((raw) {
                            try {
                              return PostData.fromServer(raw);
                            } catch (_) {
                              return null;
                            }
                          })
                          .where((p) => p != null)
                          .cast<PostData>()
                          .toList();
                } else {
                  // 전체 탭인 경우 모든 포스트 표시
                  filtered = allPosts;
                }
                print(
                  '[Feed] Base filter applied: $base, isReadOnly: $isReadOnly, filtered count: ${filtered.length}, total posts: ${allPosts.length}',
                );
              }

              // 필터링 결과가 비어있는 경우 빈 상태 메시지 표시
              if (filtered.isEmpty) {
                final theme = Theme.of(context);
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 40,
                    ),
                    child: Center(
                      child: Text(
                        '아직은 포스트가 없어요!',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ),
                );
              }

              // 카드 모드에서는 세로 리스트로 표시 (순서변경 불가)
              if (displayMode == FeedDisplayMode.card) {
                // 전체 탭이 아니면 라벨 숨김
                final isAllTab =
                    feedProvider.selectedCategoryId == null &&
                    feedProvider.selectedBase == BaseFilter.all;
                return SliverToBoxAdapter(
                  child: CardModeList(
                    title: isAllTab ? feedProvider.selectedLabel : '',
                    posts: filtered,
                    onPostTap:
                        (context, post, index) =>
                            _openPost(context, post, index),
                  ),
                );
              }

              // 이미지 전용 모드는 기존 그리드 (미분류 id=0은 시스템 카테고리지만 리오더 허용)
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: ReorderableGridList(
                    sectionTitle: feedProvider.selectedLabel,
                    items: filtered,
                    crossAxisCount: 3,
                    spacing: 6,
                    aspectRatio: 4 / 5,
                    readOnly:
                        isReadOnly ||
                        (_isSystemCategory(feedProvider.selectedLabel) &&
                            (feedProvider.selectedCategoryId != '0')),
                    scrollController: scrollController,
                    itemBuilder:
                        (context, post, index) =>
                            _buildGridThumb(context, post, index),
                    onAccept: (post, targetIndex) async {
                      final pf = context.read<ProfileFeedProvider>();
                      // 시스템 카테고리에서는 비활성화 (단, 미분류 id=0은 허용)
                      if (pf.selectedCategoryId != null &&
                          (pf.selectedCategoryId == '-1' ||
                              pf.selectedCategoryId == '-2' ||
                              pf.selectedCategoryId == '-3')) {
                        return;
                      }

                      // 선택된 사용자 카테고리 내 재배치 → 낙관적 업데이트 후 서버 저장
                      if (pf.selectedCategoryId != null) {
                        final selIdStr = pf.selectedCategoryId!;
                        final selId = int.tryParse(selIdStr);
                        if (selId != null) {
                          final posts = List<Map<String, dynamic>>.from(
                            pf.postsByCategory[selIdStr] ?? [],
                          );
                          final movedId = int.tryParse(post.id);
                          if (movedId == null) return;

                          // 기존 순서 백업
                          final prevIds =
                              posts.map<int>((p) => (p['id'] as int)).toList();

                          // 목표 인덱스 계산(제거 보정)
                          final currentIdx = prevIds.indexOf(movedId);
                          var insertAt = targetIndex.clamp(0, prevIds.length);
                          if (currentIdx != -1 && currentIdx < insertAt) {
                            insertAt = insertAt - 1;
                          }

                          // 1) 낙관적 로컬 반영
                          pf.movePostLocally(post.id, selId, insertAt);

                          // 2) 서버 저장 시도
                          try {
                            final ids = List<int>.from(prevIds);
                            ids.remove(movedId);
                            ids.insert(insertAt, movedId);
                            await BlogService().reorderPostsInCategory(
                              categoryId: selId,
                              orderedIds: ids,
                            );
                          } catch (e) {
                            // 3) 실패 시 롤백
                            pf.movePostLocally(
                              post.id,
                              selId,
                              currentIdx.clamp(0, prevIds.length - 1),
                            );
                            try {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('정렬 저장 실패: 서버 오류'),
                                ),
                              );
                            } catch (_) {}
                          }
                        }
                        return;
                      }

                      // 전체 탭 등 선택 없음 → 카테고리 간 이동 경로 유지
                      final dragSvc = context.read<PostDragDropService>();
                      final targetCatId =
                          int.tryParse(pf.selectedCategoryId ?? '0') ?? 0;
                      await dragSvc.movePostToCategoryWithContext(
                        context,
                        post,
                        targetCatId,
                        targetPosition: targetIndex,
                      );
                    },
                  ),
                ),
              );
            }

            if (!hasCategories) {
              // 카테고리가 없으면 카드 모드에서는 세로 리스트, 이미지 전용 모드는 그리드
              final isReadOnly = context.read<ProfileFeedProvider>().isReadOnly;

              if (displayMode == FeedDisplayMode.card) {
                // 전체 탭에서 다른 카테고리가 전혀 없을 때는 라벨을 숨기기 위해 빈 타이틀 전달
                return SliverToBoxAdapter(
                  child: CardModeList(
                    title: '',
                    posts: allPosts,
                    onPostTap:
                        (context, post, index) =>
                            _openPost(context, post, index),
                  ),
                );
              }

              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ReorderableGridList(
                    sectionTitle: '다른 글',
                    items: allPosts,
                    crossAxisCount: 3,
                    spacing: 6,
                    aspectRatio: 4 / 5,
                    readOnly: isReadOnly || _isSystemCategory('다른 글'),
                    scrollController: scrollController,
                    itemBuilder:
                        (context, post, index) =>
                            _buildGridThumb(context, post, index),
                    onAccept: (post, targetIndex) {
                      // 카테고리 없음: 동일 섹션 내 UI 재정렬만 수행 (필요시 저장 로직 확장 가능)
                    },
                  ),
                ),
              );
            }

            // 미분류 포스트들은 자동으로 "다른글" 섹션에 표시됨
            // TODO: 필요시 미분류 포스트 자동 할당 로직 구현

            // 카테고리가 있으면 섹션 구성
            final sections = <_FeedSectionMeta>[];

            // ProfileFeedProvider의 카테고리 데이터를 사용하여 섹션 구성
            final username = feedProvider.userInfo?['username'] as String?;

            for (final cat in feedProvider.categories) {
              final categoryId = cat['id'].toString();
              final categoryPosts =
                  feedProvider.postsByCategory[categoryId] ?? [];

              final posts =
                  categoryPosts
                      .map((raw) {
                        try {
                          return PostData.fromServer(raw);
                        } catch (_) {
                          return null;
                        }
                      })
                      .where((p) => p != null)
                      .cast<PostData>()
                      .toList();

              // 포스트가 없는 카테고리는 타인 프로필일 때만 숨김
              if (posts.isEmpty && feedProvider.isReadOnly) continue;

              final displayTitle = _getCategoryDisplayTitle(
                cat['name'],
                categoryId,
                username,
              );

              sections.add(
                _FeedSectionMeta(
                  title: displayTitle,
                  posts: posts,
                  categoryId: categoryId,
                ),
              );
            }

            if (sections.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            // 4) 세로로 섹션을 쌓고,
            //    일반 카테고리는 가로 리스트,
            //    '다른 글'는 그리드로 구성
            return SliverToBoxAdapter(
              child: ValueListenableBuilder<int?>(
                valueListenable: _categoryDropTargetIndex,
                builder: (context, dropTargetIdx, _) {
                  return Column(
                    children: [
                      ...sections.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final sec = entry.value;
                        final Widget sectionWidget =
                            (sec.categoryId == '0') // 미분류 카테고리 ID
                                ? _buildUnassignedGridSection(
                                  context,
                                  sec,
                                  displayMode,
                                  scrollController,
                                  idx,
                                  isLastSection: idx == sections.length - 1,
                                )
                                : _buildHorizontalSection(
                                  context,
                                  sec,
                                  displayMode,
                                  idx,
                                  isLastSection: idx == sections.length - 1,
                                );
                        // 섹션 간 간격 추가
                        return Padding(
                          padding: EdgeInsets.only(top: idx == 0 ? 0 : 12),
                          child: sectionWidget,
                        );
                      }).toList(),
                      // 맨 아래 드롭 영역 (마지막 섹션 다음)
                      ValueListenableBuilder<int?>(
                        valueListenable: _draggingSectionIndex,
                        builder: (context, draggingIdx, _) {
                          return DragTarget<_FeedSectionMeta>(
                            onWillAccept: (data) => data != null,
                            onMove: (details) {
                              _categoryDropTargetIndex.value = sections.length;
                            },
                            onLeave: (data) {
                              if (dropTargetIdx == sections.length) {
                                _categoryDropTargetIndex.value = null;
                              }
                            },
                            onAccept: (draggedSec) {
                              // TODO: 카테고리 순서 재정렬 구현
                              print(
                                '[Feed] 카테고리를 맨 뒤로 이동: ${draggedSec.title}',
                              );
                              _categoryDropTargetIndex.value = null;
                            },
                            builder: (context, candidateData, rejectedData) {
                              final bool showLine = _shouldShowBottomLine(
                                sectionsLength: sections.length,
                                draggingIndex: draggingIdx,
                                dropTargetIndex: dropTargetIdx,
                              );

                              return Column(
                                children: [
                                  if (showLine)
                                    Container(
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  // 항상 충분한 히트 영역 확보(에디터처럼 넉넉하게)
                                  const SizedBox(height: 96),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  // 섹션 헤더 + 가로 PageView
  Widget _buildHorizontalSection(
    BuildContext context,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
    int sectionIndex, {
    bool isLastSection = false,
  }) {
    final theme = Theme.of(context);
    final height = 200.0; // 섹션 높이(헤더 제외)
    final dragDropService = context.read<PostDragDropService>();
    final listKey = GlobalKey();
    // 섹션별 가로 스크롤 컨트롤러
    final sectionId = sec.title;
    final hController = context
        .read<PostDragDropService>()
        .horizontalControllerFor(sectionId);
    double? _cachedCardWidth;

    final isReadOnly = context.read<ProfileFeedProvider>().isReadOnly;
    final username =
        context.read<ProfileFeedProvider>().userInfo?['username'] as String?;

    // 카드 모드에서는 새로운 CardModeList 사용
    if (displayMode == FeedDisplayMode.card) {
      return ValueListenableBuilder<int?>(
        valueListenable: _categoryDropTargetIndex,
        builder: (context, dropTargetIdx, _) {
          final currentSectionIndex = sectionIndex; // sectionIndex 사용

          return DragTarget<_FeedSectionMeta>(
            onWillAccept: (data) {
              if (isReadOnly) return false;
              return data != null && data.categoryId != sec.categoryId;
            },
            onMove: (details) {
              try {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final dy = details.offset.dy; // global y
                  final topLeft = box.localToGlobal(Offset.zero);
                  final rect = Rect.fromLTWH(
                    topLeft.dx,
                    topLeft.dy,
                    box.size.width,
                    box.size.height,
                  );
                  final centerY = rect.center.dy;
                  final below = dy >= centerY;

                  if (below && isLastSection) {
                    // 마지막 섹션에서 아래로 드래그하면 바닥 드롭 영역으로
                    _categoryDropTargetIndex.value = currentSectionIndex + 1;
                  } else {
                    _categoryDropTargetIndex.value =
                        below ? currentSectionIndex + 1 : currentSectionIndex;
                  }
                } else {
                  _categoryDropTargetIndex.value = currentSectionIndex;
                }
              } catch (_) {
                _categoryDropTargetIndex.value = currentSectionIndex;
              }
            },
            onLeave: (data) {
              _categoryDropTargetIndex.value = null;
            },
            onAccept: (draggedSec) {
              // 읽기 전용이면 아무것도 하지 않음
              print(
                '[Feed] onAccept - isReadOnly: $isReadOnly, draggedSec: ${draggedSec.title}',
              );
              if (isReadOnly) return;

              // 카테고리 순서 재정렬 (다른글 포함)
              final catProvider = context.read<ProfileFeedProvider>();
              if (draggedSec.categoryId != null && sec.categoryId != null) {
                final List<String> prevOrder = List.from(
                  catProvider.categories.map((c) => c['id'].toString()),
                );
                final List<String> newOrder = List.from(prevOrder);
                final draggedIdx = newOrder.indexOf(draggedSec.categoryId!);
                final targetRaw =
                    (_categoryDropTargetIndex.value ?? currentSectionIndex);
                final targetIdx = targetRaw.clamp(0, newOrder.length);

                // debug
                // ignore: avoid_print
                print('[Feed] 카테고리를 맨 뒤로 이동: ${draggedSec.title}');
                // ignore: avoid_print
                print(
                  '[Feed] draggedIdx=$draggedIdx targetRaw=$targetRaw len=${newOrder.length}',
                );

                if (draggedIdx != -1 && targetIdx != -1) {
                  final wantTail = targetRaw >= newOrder.length;
                  if (wantTail) {
                    newOrder.removeAt(draggedIdx);
                    newOrder.add(draggedSec.categoryId!);
                  } else if (draggedIdx != targetIdx) {
                    newOrder.removeAt(draggedIdx);
                    final insertIdx = targetIdx.clamp(0, newOrder.length);
                    newOrder.insert(insertIdx, draggedSec.categoryId!);
                  }

                  if (!_stringListEquals(newOrder, prevOrder)) {
                    context.read<ProfileFeedProvider>().reorderAllSections(
                      newOrder,
                    );
                  }
                }
              }
              _categoryDropTargetIndex.value = null;
            },
            builder: (context, candidateData, rejectedData) {
              return ValueListenableBuilder<int?>(
                valueListenable: _draggingSectionIndex,
                builder: (context, draggingIdx, _) {
                  final showDropLine =
                      candidateData.isNotEmpty &&
                      _shouldShowDropLine(
                        currentIndex: currentSectionIndex,
                        draggingIndex: draggingIdx,
                        dropTargetIndex: dropTargetIdx,
                      );

                  return Column(
                    children: [
                      if (showDropLine)
                        Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _isDraggingCategory,
                        builder: (context, isDragging, _) {
                          return Opacity(
                            opacity: isDragging ? 0.3 : 1.0,
                            child: CardModeList(
                              // 전체 탭 카드뷰: 각 카테고리 제목 표시
                              title: sec.title,
                              posts: sec.posts,
                              sectionMeta: sec,
                              feedbackBuilder:
                                  (ctx, meta) => _buildCategoryFeedback(
                                    ctx,
                                    theme,
                                    meta,
                                    displayMode,
                                  ),
                              onDragStarted: () {
                                _isDraggingCategory.value = true;
                                _draggingSectionIndex.value = sectionIndex;
                                onDragStateChanged?.call();
                              },
                              onDragUpdate: (details) {
                                if (_mainScrollController != null &&
                                    _mainScrollController!.hasClients) {
                                  final screenHeight =
                                      MediaQuery.of(context).size.height;
                                  final globalY = details.globalPosition.dy;
                                  const edge = 100.0;
                                  const speed = 10.0;

                                  final pos = _mainScrollController!.position;
                                  if (globalY < edge) {
                                    final next = (pos.pixels - speed).clamp(
                                      0.0,
                                      pos.maxScrollExtent,
                                    );
                                    if (next != pos.pixels)
                                      _mainScrollController!.jumpTo(next);
                                  } else if (globalY > screenHeight - edge) {
                                    final next = (pos.pixels + speed).clamp(
                                      0.0,
                                      pos.maxScrollExtent,
                                    );
                                    if (next != pos.pixels)
                                      _mainScrollController!.jumpTo(next);
                                  }
                                }
                              },
                              onDragEnd: () {
                                _isDraggingCategory.value = false;
                                _categoryDropTargetIndex.value = null;
                                _draggingSectionIndex.value = null;
                                onDragStateChanged?.call();
                              },
                              onPostTap:
                                  (context, post, index) =>
                                      _openPost(context, post, index),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      );
    }
    return DragTarget<PostData>(
      onWillAccept: (data) {
        if (isReadOnly) return false;
        return data != null;
      },
      onAccept: (data) async {
        // 섹션(카테고리) 안으로 드롭
        dragDropService.setDropTarget(sec.title);

        final targetCatId = int.tryParse(sec.categoryId ?? '0') ?? 0;
        int targetIndex = (dragDropService.reorderTargetIndex ??
                sec.posts.length)
            .clamp(0, sec.posts.length);

        // 동일 섹션 내 재정렬 여부 판별
        final curIdx = sec.posts.indexWhere((p) => p.id == data.id);
        if (curIdx != -1) {
          // 동일 섹션 재배치 → reorder 호출
          if (targetIndex == curIdx || targetIndex == curIdx + 1) {
            dragDropService.setReorderTargetIndex(null);
            return;
          }

          final ids =
              sec.posts.map<int>((p) => int.tryParse(p.id) ?? -1).toList();
          ids.removeWhere((v) => v == -1);
          final movedId = int.tryParse(data.id);
          if (movedId != null) {
            ids.remove(movedId);
            // curIdx < targetIndex면 삭제로 한 칸 당겨졌으므로 보정
            final insertAt =
                (curIdx < targetIndex) ? targetIndex - 1 : targetIndex;
            ids.insert(insertAt.clamp(0, ids.length), movedId);

            await BlogService().reorderPostsInCategory(
              categoryId: targetCatId,
              orderedIds: ids,
            );
            // 로컬 반영
            context.read<ProfileFeedProvider>().movePostLocally(
              data.id,
              targetCatId,
              insertAt,
            );
          }
        } else {
          // 다른 섹션에서 넘어온 경우 → move API 사용
          await context
              .read<PostDragDropService>()
              .movePostToCategoryWithContext(
                context,
                data,
                targetCatId,
                targetPosition: targetIndex,
              );
        }

        // 프리뷰 슬롯 리셋
        dragDropService.setReorderTargetIndex(null);
      },
      onMove: (details) {
        // 타겟 표시 + 인서트 위치 계산 + 섹션별 수평 오토 스크롤
        dragDropService.setDropTarget(sec.title);
        try {
          final box = listKey.currentContext?.findRenderObject() as RenderBox?;
          if (box != null && _cachedCardWidth != null) {
            final local = box.globalToLocal(details.offset);
            const sep = 5.0;
            final viewportX = local.dx.clamp(0.0, box.size.width);
            final scrollX =
                hController.hasClients ? hController.position.pixels : 0.0;
            final totalX = scrollX + viewportX;
            final raw = totalX / (_cachedCardWidth! + sep);
            final idx = raw.floor().clamp(0, sec.posts.length);
            dragDropService.setReorderTargetIndex(idx);

            // 섹션 가로 오토 스크롤
            if (hController.hasClients) {
              const edge = 80.0;
              const speed = 6.0; // 느린 가로 오토 스크롤 속도
              final pos = hController.position;
              if (local.dx < edge) {
                final next = (pos.pixels - speed).clamp(
                  0.0,
                  pos.maxScrollExtent,
                );
                if (next != pos.pixels) hController.jumpTo(next);
              } else if (local.dx > box.size.width - edge) {
                final next = (pos.pixels + speed).clamp(
                  0.0,
                  pos.maxScrollExtent,
                );
                if (next != pos.pixels) hController.jumpTo(next);
              }
            }
          }
        } catch (_) {}
      },
      onLeave: (data) {
        // 프리뷰 슬롯 리셋만 수행
        dragDropService.setReorderTargetIndex(null);
      },
      builder: (context, candidateData, rejectedData) {
        return ValueListenableBuilder<int?>(
          valueListenable: _categoryDropTargetIndex,
          builder: (context, dropTargetIdx, _) {
            // 현재 섹션의 인덱스 찾기
            final currentSectionIndex = sectionIndex; // sectionIndex 사용

            return DragTarget<_FeedSectionMeta>(
              onWillAccept: (data) {
                if (isReadOnly) return false;
                return data != null && data.categoryId != sec.categoryId;
              },
              onMove: (details) {
                try {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    final dy = details.offset.dy; // global y
                    final topLeft = box.localToGlobal(Offset.zero);
                    final rect = Rect.fromLTWH(
                      topLeft.dx,
                      topLeft.dy,
                      box.size.width,
                      box.size.height,
                    );
                    final centerY = rect.center.dy;
                    final below = dy >= centerY;

                    if (below && isLastSection) {
                      // 마지막 섹션에서 아래로 드래그하면 바닥 드롭 영역으로
                      _categoryDropTargetIndex.value = currentSectionIndex + 1;
                    } else {
                      _categoryDropTargetIndex.value =
                          below ? currentSectionIndex + 1 : currentSectionIndex;
                    }
                  } else {
                    _categoryDropTargetIndex.value = currentSectionIndex;
                  }
                } catch (_) {
                  _categoryDropTargetIndex.value = currentSectionIndex;
                }
              },
              onLeave: (data) {
                _categoryDropTargetIndex.value = null;
              },
              onAccept: (draggedSec) async {
                // 읽기 전용이면 아무것도 하지 않음
                if (isReadOnly) return;

                final catProvider = context.read<ProfileFeedProvider>();
                if (draggedSec.categoryId != null && sec.categoryId != null) {
                  final List<String> prevOrder = List.from(
                    catProvider.categories.map((c) => c['id'].toString()),
                  );
                  final List<String> newOrder = List.from(prevOrder);
                  final draggedIdx = newOrder.indexOf(draggedSec.categoryId!);
                  final targetRaw =
                      (_categoryDropTargetIndex.value ?? currentSectionIndex);
                  final targetIdx = targetRaw.clamp(0, newOrder.length);

                  // debug
                  // ignore: avoid_print
                  print('[Feed] 카테고리를 맨 뒤로 이동: ${draggedSec.title}');
                  // ignore: avoid_print
                  print(
                    '[Feed] draggedIdx=$draggedIdx targetRaw=$targetRaw len=${newOrder.length}',
                  );

                  if (draggedIdx != -1 && targetIdx != -1) {
                    final wantTail = targetRaw >= newOrder.length;
                    if (wantTail) {
                      newOrder.removeAt(draggedIdx);
                      newOrder.add(draggedSec.categoryId!);
                    } else if (draggedIdx != targetIdx) {
                      newOrder.removeAt(draggedIdx);
                      final insertIdx = targetIdx.clamp(0, newOrder.length);
                      newOrder.insert(insertIdx, draggedSec.categoryId!);
                    }

                    if (!_stringListEquals(newOrder, prevOrder)) {
                      final pf = context.read<ProfileFeedProvider>();
                      // 인스턴스 동일성/호출 여부 확인 로그
                      // ignore: avoid_print
                      print(
                        'PF#${identityHashCode(pf)} call reorder, newOrder=$newOrder',
                      );
                      await pf.reorderAllSections(newOrder);
                    } else {
                      // ignore: avoid_print
                      print('[Feed] skip: order unchanged');
                    }
                  }
                }
                _categoryDropTargetIndex.value = null;
              },
              builder: (ctx2, candidateData2, rejectedData2) {
                return ValueListenableBuilder<int?>(
                  valueListenable: _draggingSectionIndex,
                  builder: (context, draggingIdx, _) {
                    final showDropLine =
                        candidateData2.isNotEmpty &&
                        _shouldShowDropLine(
                          currentIndex: currentSectionIndex,
                          draggingIndex: draggingIdx,
                          dropTargetIndex: dropTargetIdx,
                        );

                    return Column(
                      children: [
                        // 드롭 프리뷰 라인
                        if (showDropLine)
                          Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        if (sec.posts.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 읽기 전용일 때는 드래그 비활성화
                                if (isReadOnly)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _getCategoryDisplayTitle(
                                              sec.title,
                                              sec.categoryId!,
                                              username,
                                            ),
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 18,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  LongPressDraggable<_FeedSectionMeta>(
                                    data: sec,
                                    dragAnchorStrategy:
                                        pointerDragAnchorStrategy,
                                    onDragStarted: () {
                                      _isDraggingCategory.value = true;
                                      _draggingSectionIndex.value =
                                          sectionIndex;
                                    },
                                    onDragUpdate: (details) {
                                      // 절대 좌표 기준 자동 스크롤
                                      if (_mainScrollController != null &&
                                          _mainScrollController!.hasClients) {
                                        final screenHeight =
                                            MediaQuery.of(context).size.height;
                                        final globalY =
                                            details.globalPosition.dy;
                                        const edge = 100.0;
                                        const double minSpeed = 16.0;
                                        const double maxSpeed = 58.0;

                                        final pos =
                                            _mainScrollController!.position;
                                        if (globalY < edge) {
                                          final ratio = (1.0 - (globalY / edge))
                                              .clamp(0.0, 1.0);
                                          final speed =
                                              minSpeed +
                                              (maxSpeed - minSpeed) * ratio;
                                          final next = (pos.pixels - speed)
                                              .clamp(0.0, pos.maxScrollExtent);
                                          if (next != pos.pixels)
                                            _mainScrollController!.jumpTo(next);
                                        } else if (globalY >
                                            screenHeight - edge) {
                                          final ratio = (1.0 -
                                                  ((screenHeight - globalY) /
                                                      edge))
                                              .clamp(0.0, 1.0);
                                          final speed =
                                              minSpeed +
                                              (maxSpeed - minSpeed) * ratio;
                                          final next = (pos.pixels + speed)
                                              .clamp(0.0, pos.maxScrollExtent);
                                          if (next != pos.pixels)
                                            _mainScrollController!.jumpTo(next);
                                        }
                                      }
                                    },
                                    onDragEnd: (details) {
                                      _isDraggingCategory.value = false;
                                      _categoryDropTargetIndex.value = null;
                                      onDragStateChanged?.call();
                                    },
                                    feedback: _buildCategoryFeedback(
                                      context,
                                      theme,
                                      sec,
                                      displayMode,
                                    ),
                                    // 드래그 중에도 섹션은 그대로 유지
                                    childWhenDragging: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 5,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sec.title,
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 18,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.8),
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 5,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _getCategoryDisplayTitle(
                                                sec.title,
                                                sec.categoryId!,
                                                context
                                                    .read<UserProvider>()
                                                    .currentUser
                                                    ?.username,
                                              ),
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 18,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.8),
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                if (sec.posts.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      8,
                                      4,
                                      16,
                                    ),
                                    child: Container(
                                      height: 150,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.background
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: theme.colorScheme.surface
                                              .withOpacity(0.1),
                                          width: 0.7,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '글이 아직 없어요',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.6),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    height: height,
                                    child: Padding(
                                      padding: EdgeInsets.zero,
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final double cardWidth =
                                              displayMode ==
                                                      FeedDisplayMode.imageOnly
                                                  ? height * 4 / 5
                                                  : math.min(
                                                    constraints.maxWidth,
                                                    360.0,
                                                  );
                                          _cachedCardWidth = cardWidth;
                                          return Consumer<PostDragDropService>(
                                            builder: (context, dragSvc, _) {
                                              // 드래그 중이고 현재 섹션 위에 있을 때만 목표 인덱스 표시
                                              final int? rawReorderIndex =
                                                  (dragSvc.isDragging &&
                                                          dragSvc.targetCategory ==
                                                              sec.title)
                                                      ? dragSvc
                                                          .reorderTargetIndex
                                                      : null;

                                              // 원래 자기 위치면 스페이싱 미표시
                                              int? reorderIndex =
                                                  rawReorderIndex;
                                              if (dragSvc.isDragging &&
                                                  dragSvc.targetCategory ==
                                                      sec.title &&
                                                  rawReorderIndex != null &&
                                                  dragSvc.draggedPost != null) {
                                                final curIdx = sec.posts
                                                    .indexWhere(
                                                      (p) =>
                                                          p.id ==
                                                          dragSvc
                                                              .draggedPost!
                                                              .id,
                                                    );
                                                if (curIdx != -1 &&
                                                    (rawReorderIndex ==
                                                            curIdx ||
                                                        rawReorderIndex ==
                                                            curIdx + 1)) {
                                                  reorderIndex = null;
                                                }
                                              }

                                              return ValueListenableBuilder<
                                                bool
                                              >(
                                                valueListenable:
                                                    _isDraggingCategory,
                                                builder: (
                                                  context,
                                                  isDragging,
                                                  _,
                                                ) {
                                                  return Opacity(
                                                    opacity:
                                                        isDragging ? 0.3 : 1.0,
                                                    child: Container(
                                                      margin: EdgeInsets.only(
                                                        bottom: 14,
                                                      ),
                                                      key: listKey,
                                                      child: ListView.builder(
                                                        controller: hController,
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        itemCount:
                                                            sec.posts.length +
                                                            ((reorderIndex !=
                                                                    null)
                                                                ? 1
                                                                : 0),
                                                        itemBuilder: (
                                                          context,
                                                          i,
                                                        ) {
                                                          // 인서트 가상 슬롯
                                                          if (reorderIndex !=
                                                                  null &&
                                                              i ==
                                                                  reorderIndex) {
                                                            return const SizedBox(
                                                              width: 18,
                                                            );
                                                          }

                                                          // 실제 데이터 인덱스로 매핑
                                                          final dataIndex =
                                                              (reorderIndex !=
                                                                          null &&
                                                                      i > reorderIndex)
                                                                  ? i - 1
                                                                  : i;
                                                          final post =
                                                              sec.posts[dataIndex];
                                                          return Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  right: 5,
                                                                ),
                                                            child: SizedBox(
                                                              width: cardWidth,
                                                              child:
                                                                  displayMode ==
                                                                          FeedDisplayMode
                                                                              .card
                                                                      ? _buildHorizontalCard(
                                                                        context,
                                                                        post,
                                                                        dataIndex,
                                                                      )
                                                                      : _buildImageOnlyCard(
                                                                        context,
                                                                        post,
                                                                        dataIndex,
                                                                      ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (sec.posts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 100),
                            child: Column(
                              children: [
                                Text(
                                  '아직은 포스트가 없어요!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w300,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // 카테고리 드래그 feedback 위젯
  Widget _buildCategoryFeedback(
    BuildContext context,
    ThemeData theme,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
  ) {
    return Transform.scale(
      scale: 0.8,
      child: Container(
        width: MediaQuery.of(context).size.width - 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildSectionPreview(context, theme, sec, displayMode),
        ),
      ),
    );
  }

  // 섹션 미리보기 (헤더 + 콘텐츠)
  Widget _buildSectionPreview(
    BuildContext context,
    ThemeData theme,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  sec.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 콘텐츠 미리보기
        _buildContentPreview(context, theme, sec, displayMode),
      ],
    );
  }

  // 콘텐츠 미리보기
  Widget _buildContentPreview(
    BuildContext context,
    ThemeData theme,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
  ) {
    if (sec.posts.isEmpty) {
      return Container(
        height: 200,
        child: Center(
          child: Text(
            '빈 섹션',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // 최대 3개까지만 미리보기
    final previewPosts = sec.posts.take(3).toList();

    return SizedBox(
      height: displayMode == FeedDisplayMode.card ? 240 : 200, // 카드 모드일 때 높이 증가
      child: Stack(
        children: [
          // 리스트뷰
          ListView.builder(
            padding:
                displayMode == FeedDisplayMode.card
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ), // 이미지 모드일 때 패딩 추가
            scrollDirection:
                displayMode == FeedDisplayMode.card
                    ? Axis.vertical
                    : Axis.horizontal,
            itemCount: previewPosts.length,
            itemBuilder: (context, index) {
              final post = previewPosts[index];
              if (displayMode == FeedDisplayMode.card) {
                // 카드 모드: 세로 방향, 전체 너비, 패딩 제거
                return Container(
                  width: double.infinity,
                  height: 150,
                  margin: EdgeInsets.zero, // 패딩 제거
                  child: _buildPostCard(context, theme, post, displayMode),
                );
              } else {
                // 이미지 모드: 가로 방향, 4:5 비율
                return Container(
                  width: 100, // 4:5 비율을 위해 너비 조정
                  height: 80, // 4:5 비율 (100 * 4/5 = 80)
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildPostCard(context, theme, post, displayMode),
                );
              }
            },
          ),
          // +n 표식 (3개 이상일 때만)
          if (sec.posts.length > 3)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '+${sec.posts.length - 3}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 포스트 카드 (실제 카드 모드/이미지 모드 디자인 재사용)
  Widget _buildPostCard(
    BuildContext context,
    ThemeData theme,
    PostData post,
    FeedDisplayMode displayMode,
  ) {
    if (displayMode == FeedDisplayMode.card) {
      // 카드 모드: 실제 CardModeList와 정확히 동일한 디자인
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              // 블러 배경 이미지
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: post.thumbnailImageUrl,
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => Container(
                        color: theme.colorScheme.surface.withOpacity(0.1),
                      ),
                  errorWidget:
                      (context, url, error) => const ImageErrorPlaceholder(),
                ),
              ),
              // 블러 효과
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.black.withOpacity(0.8)),
                ),
              ),
              // 콘텐츠
              Row(
                children: [
                  // 왼쪽: 이미지 영역
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        child: CachedNetworkImage(
                          imageUrl: post.thumbnailImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 150,
                          placeholder:
                              (context, url) => Container(
                                color: theme.colorScheme.surface.withOpacity(
                                  0.1,
                                ),
                                child: ShimmerBox(
                                  width: double.infinity,
                                  height: 180,
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                          errorWidget:
                              (context, url, error) =>
                                  const ImageErrorPlaceholder(),
                        ),
                      ),
                    ),
                  ),
                  // 오른쪽: 콘텐츠 영역
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 16,
                        top: 16,
                        bottom: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 제목
                              Text(
                                post.title,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8),
                              // 요약 (하드코딩)
                              Text(
                                '이벤트에 대한 간단한 설명과 함께 참여자들의 관심을 끌 수 있는 내용을 포함합니다.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          // 좋아요, 조회수
                          Row(
                            children: [
                              Icon(
                                Icons.favorite_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${post.likeCount}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                              SizedBox(width: 12),
                              Icon(
                                Icons.visibility_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${post.viewCount}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      // 이미지 온리 모드: 실제 이미지 온리 뷰와 동일한 디자인
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            placeholder:
                (context, url) => Container(
                  color: theme.colorScheme.surfaceVariant,
                  child: Icon(
                    Icons.image,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
            errorWidget: (context, url, error) => const ImageErrorPlaceholder(),
          ),
        ),
      );
    }
  }

  // '미분류' 섹션: 헤더 + 3열 그리드
  Widget _buildUnassignedGridSection(
    BuildContext context,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
    ScrollController? scrollController,
    int sectionIndex, {
    bool isLastSection = false,
  }) {
    final theme = Theme.of(context);
    final isReadOnly = context.read<ProfileFeedProvider>().isReadOnly;

    // 카드 모드에서는 CardModeList 사용 (드래그 가능)
    if (displayMode == FeedDisplayMode.card) {
      return ValueListenableBuilder<int?>(
        valueListenable: _categoryDropTargetIndex,
        builder: (context, dropTargetIdx, _) {
          final currentSectionIndex = sectionIndex;

          return DragTarget<_FeedSectionMeta>(
            onWillAccept: (data) {
              if (isReadOnly) return false;
              return data != null;
            },
            onMove: (details) {
              try {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final dy = details.offset.dy; // global y
                  final topLeft = box.localToGlobal(Offset.zero);
                  final rect = Rect.fromLTWH(
                    topLeft.dx,
                    topLeft.dy,
                    box.size.width,
                    box.size.height,
                  );
                  final centerY = rect.center.dy;
                  final below = dy >= centerY;

                  if (below && isLastSection) {
                    // 마지막 섹션에서 아래로 드래그하면 바닥 드롭 영역으로
                    _categoryDropTargetIndex.value = currentSectionIndex + 1;
                  } else {
                    _categoryDropTargetIndex.value =
                        below ? currentSectionIndex + 1 : currentSectionIndex;
                  }
                } else {
                  _categoryDropTargetIndex.value = currentSectionIndex;
                }
              } catch (_) {
                _categoryDropTargetIndex.value = currentSectionIndex;
              }
            },
            onLeave: (data) {
              _categoryDropTargetIndex.value = null;
            },
            onAccept: (draggedSec) async {
              // 읽기 전용이면 아무것도 하지 않음
              if (isReadOnly) return;

              final catProvider = context.read<ProfileFeedProvider>();
              if (draggedSec.categoryId != null) {
                final List<String> prevOrder = List.from(
                  catProvider.categories.map((c) => c['id'].toString()),
                );
                final List<String> newOrder = List.from(prevOrder);
                final draggedIdx = newOrder.indexOf(draggedSec.categoryId!);
                final targetRaw =
                    (_categoryDropTargetIndex.value ?? currentSectionIndex);
                final targetIdx = targetRaw.clamp(0, newOrder.length);

                // debug
                // ignore: avoid_print
                print('[Feed] 카테고리를 맨 뒤로 이동: ${draggedSec.title}');
                // ignore: avoid_print
                print(
                  '[Feed] draggedIdx=$draggedIdx targetRaw=$targetRaw len=${newOrder.length}',
                );

                if (draggedIdx != -1 && targetIdx != -1) {
                  final wantTail = targetRaw >= newOrder.length;
                  if (wantTail) {
                    newOrder.removeAt(draggedIdx);
                    newOrder.add(draggedSec.categoryId!);
                  } else if (draggedIdx != targetIdx) {
                    newOrder.removeAt(draggedIdx);
                    final insertIdx = targetIdx.clamp(0, newOrder.length);
                    newOrder.insert(insertIdx, draggedSec.categoryId!);
                  }
                  if (!_stringListEquals(newOrder, prevOrder)) {
                    await catProvider.reorderAllSections(newOrder);
                  }
                }
              }
              _categoryDropTargetIndex.value = null;
            },
            builder: (context, candidateData, rejectedData) {
              return ValueListenableBuilder<int?>(
                valueListenable: _draggingSectionIndex,
                builder: (context, draggingIdx, _) {
                  final showDropLine =
                      candidateData.isNotEmpty &&
                      dropTargetIdx == currentSectionIndex &&
                      currentSectionIndex != draggingIdx &&
                      currentSectionIndex !=
                          (draggingIdx != null ? draggingIdx + 1 : -999);

                  return Column(
                    children: [
                      if (showDropLine)
                        Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _isDraggingCategory,
                        builder: (context, isDragging, _) {
                          return Opacity(
                            opacity: isDragging ? 0.3 : 1.0,
                            child: CardModeList(
                              title: sec.title,
                              posts: sec.posts,
                              sectionMeta: sec,
                              feedbackBuilder:
                                  (ctx, meta) => _buildCategoryFeedback(
                                    ctx,
                                    theme,
                                    meta,
                                    displayMode,
                                  ),
                              onDragStarted: () {
                                _isDraggingCategory.value = true;
                                _draggingSectionIndex.value = sectionIndex;
                                onDragStateChanged?.call();
                              },
                              onDragUpdate: (details) {
                                if (_mainScrollController != null &&
                                    _mainScrollController!.hasClients) {
                                  final screenHeight =
                                      MediaQuery.of(context).size.height;
                                  final globalY = details.globalPosition.dy;
                                  const edge = 100.0;
                                  const speed = 10.0;

                                  final pos = _mainScrollController!.position;
                                  if (globalY < edge) {
                                    final next = (pos.pixels - speed).clamp(
                                      0.0,
                                      pos.maxScrollExtent,
                                    );
                                    if (next != pos.pixels)
                                      _mainScrollController!.jumpTo(next);
                                  } else if (globalY > screenHeight - edge) {
                                    final next = (pos.pixels + speed).clamp(
                                      0.0,
                                      pos.maxScrollExtent,
                                    );
                                    if (next != pos.pixels)
                                      _mainScrollController!.jumpTo(next);
                                  }
                                }
                              },
                              onDragEnd: () {
                                _isDraggingCategory.value = false;
                                _categoryDropTargetIndex.value = null;
                                _draggingSectionIndex.value = null;
                                onDragStateChanged?.call();
                              },
                              onPostTap:
                                  (context, post, index) =>
                                      _openPost(context, post, index),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      );
    }

    // 이미지 전용 모드 - 그리드 (드래그 가능)
    return ValueListenableBuilder<int?>(
      valueListenable: _categoryDropTargetIndex,
      builder: (context, dropTargetIdx, _) {
        final currentSectionIndex = sectionIndex;

        return DragTarget<_FeedSectionMeta>(
          onWillAccept: (data) {
            if (isReadOnly) return false;
            return data != null && data.categoryId != sec.categoryId;
          },
          onMove: (details) {
            try {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final dy = details.offset.dy;
                final tl = box.localToGlobal(Offset.zero);
                final rect = Rect.fromLTWH(
                  tl.dx,
                  tl.dy,
                  box.size.width,
                  box.size.height,
                );
                final centerY = rect.center.dy;
                final below = dy >= centerY;

                if (below && isLastSection) {
                  // 마지막 섹션에서 아래로 드래그하면 바닥 드롭 영역으로
                  _categoryDropTargetIndex.value = currentSectionIndex + 1;
                } else {
                  _categoryDropTargetIndex.value =
                      below ? currentSectionIndex + 1 : currentSectionIndex;
                }
              } else {
                _categoryDropTargetIndex.value = currentSectionIndex;
              }
            } catch (_) {
              _categoryDropTargetIndex.value = currentSectionIndex;
            }
          },
          onLeave: (data) {
            _categoryDropTargetIndex.value = null;
          },
          onAccept: (draggedSec) async {
            // 읽기 전용이면 아무것도 하지 않음
            if (isReadOnly) return;

            final catProvider = context.read<ProfileFeedProvider>();
            if (draggedSec.categoryId != null) {
              final List<String> newOrder = List.from(
                catProvider.categories.map((c) => c['id'].toString()),
              );
              final draggedIdx = newOrder.indexOf(draggedSec.categoryId!);
              final targetIdx = (_categoryDropTargetIndex.value ??
                      currentSectionIndex)
                  .clamp(0, newOrder.length);

              if (draggedIdx != -1 &&
                  targetIdx != -1 &&
                  draggedIdx != targetIdx) {
                newOrder.removeAt(draggedIdx);
                final insertIdx = targetIdx.clamp(0, newOrder.length);
                newOrder.insert(insertIdx, draggedSec.categoryId!);
                await catProvider.reorderAllSections(newOrder);
              }
            }
            _categoryDropTargetIndex.value = null;
          },
          builder: (context, candidateData, rejectedData) {
            return ValueListenableBuilder<int?>(
              valueListenable: _draggingSectionIndex,
              builder: (context, draggingIdx, _) {
                final showDropLine =
                    candidateData.isNotEmpty &&
                    _shouldShowDropLine(
                      currentIndex: currentSectionIndex,
                      draggingIndex: draggingIdx,
                      dropTargetIndex: dropTargetIdx,
                    );

                return Column(
                  children: [
                    if (showDropLine)
                      Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 읽기 전용일 때는 드래그 비활성화
                          if (isReadOnly)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                              child: Row(
                                children: [
                                  Text(
                                    sec.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            LongPressDraggable<_FeedSectionMeta>(
                              data: sec,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              onDragStarted: () {
                                _isDraggingCategory.value = true;
                                _draggingSectionIndex.value = sectionIndex;
                              },
                              onDragUpdate: (details) {
                                if (_mainScrollController != null &&
                                    _mainScrollController!.hasClients) {
                                  final screenHeight =
                                      MediaQuery.of(context).size.height;
                                  final globalY = details.globalPosition.dy;
                                  const edge = 100.0;
                                  const speed = 10.0;

                                  final pos = _mainScrollController!.position;
                                  if (globalY < edge) {
                                    final next = (pos.pixels - speed).clamp(
                                      0.0,
                                      pos.maxScrollExtent,
                                    );
                                    if (next != pos.pixels)
                                      _mainScrollController!.jumpTo(next);
                                  } else if (globalY > screenHeight - edge) {
                                    final next = (pos.pixels + speed).clamp(
                                      0.0,
                                      pos.maxScrollExtent,
                                    );
                                    if (next != pos.pixels)
                                      _mainScrollController!.jumpTo(next);
                                  }
                                }
                              },
                              onDragEnd: (details) {
                                _isDraggingCategory.value = false;
                                _categoryDropTargetIndex.value = null;
                                _draggingSectionIndex.value = null;
                                onDragStateChanged?.call();
                              },
                              feedback: _buildCategoryFeedback(
                                context,
                                theme,
                                sec,
                                displayMode,
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    6,
                                    16,
                                    4,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        sec.title,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 18,
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.8),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      sec.title,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.8),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (sec.posts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    '이 카테고리에 글이 없어요',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            ValueListenableBuilder<bool>(
                              valueListenable: _isDraggingCategory,
                              builder: (context, isDragging, _) {
                                return Opacity(
                                  opacity: isDragging ? 0.3 : 1.0,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      1,
                                      2,
                                      1,
                                      8,
                                    ),
                                    child: ReorderableGridList(
                                      // 미분류는 섹션 타이틀 숨김
                                      sectionTitle: '',
                                      items: sec.posts,
                                      crossAxisCount: 3,
                                      spacing: 6,
                                      aspectRatio: 4 / 5,
                                      readOnly:
                                          isReadOnly ||
                                          _isSystemCategory(sec.title),
                                      scrollController: scrollController,
                                      itemBuilder:
                                          (context, post, index) =>
                                              _buildGridThumb(
                                                context,
                                                post,
                                                index,
                                              ),
                                      onAccept: (post, targetIndex) async {
                                        // 미분류(0)도 카테고리로 취급: reorder 엔드포인트로 확정 저장
                                        final feed =
                                            context.read<ProfileFeedProvider>();
                                        final posts =
                                            List<Map<String, dynamic>>.from(
                                              feed.postsByCategory['0'] ?? [],
                                            );

                                        final movedId = int.tryParse(post.id);
                                        if (movedId == null) return;

                                        final ids =
                                            posts
                                                .map<int>(
                                                  (p) => (p['id'] as int),
                                                )
                                                .toList();
                                        ids.remove(movedId);
                                        final insertAt = targetIndex.clamp(
                                          0,
                                          ids.length,
                                        );
                                        ids.insert(insertAt, movedId);

                                        await BlogService()
                                            .reorderPostsInCategory(
                                              categoryId: 0,
                                              orderedIds: ids,
                                            );

                                        // 로컬 반영
                                        feed.movePostLocally(
                                          post.id,
                                          0,
                                          insertAt,
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // 가로 카드: 썸네일 + 텍스트 미리보기
  Widget _buildHorizontalCard(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);
    final dragDropService = context.read<PostDragDropService>();
    final isReadOnly = context.read<ProfileFeedProvider>().isReadOnly;

    if (isReadOnly) {
      return _buildHorizontalCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      );
    }

    return LongPressDraggable<PostData>(
      data: post,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        dragDropService.beginDrag(post);
      },
      onDragUpdate: (details) {
        dragDropService.updateDragPosition(details.globalPosition);
      },
      onDragEnd: (details) {
        dragDropService.endDrag();
      },
      feedback: _buildDragFeedbackCard(context, post),
      // 드래그 중에도 원래 카드 UI 유지
      childWhenDragging: _buildHorizontalCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      ),
      child: _buildHorizontalCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      ),
    );
  }

  Widget _buildHorizontalCardBody(
    BuildContext context,
    ThemeData theme,
    PostData post,
    int index, {
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: CachedNetworkImage(
                    imageUrl: post.thumbnailImageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        post.title,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post.parsedContent,
                        style: TextStyle(
                          fontWeight: FontWeight.w300,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 이미지 전용 카드 (썸네일만 꽉 차게)
  Widget _buildImageOnlyCard(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);
    final dragDropService = context.read<PostDragDropService>();
    final isReadOnly = context.read<ProfileFeedProvider>().isReadOnly;

    if (isReadOnly) {
      return _buildImageOnlyCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      );
    }

    return LongPressDraggable<PostData>(
      data: post,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        dragDropService.beginDrag(post);
      },
      onDragUpdate: (details) {
        dragDropService.updateDragPosition(details.globalPosition);
      },
      onDragEnd: (details) {
        dragDropService.endDrag();
      },
      feedback: _buildDragFeedbackImage(context, post),
      // 드래그 중에도 원래 셀은 그대로 보여주고, 드랍 시 반영
      childWhenDragging: _buildImageOnlyCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      ),
      child: _buildImageOnlyCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      ),
    );
  }

  Widget _buildImageOnlyCardBody(
    BuildContext context,
    ThemeData theme,
    PostData post,
    int index, {
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            placeholder:
                (context, url) => ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.circular(14),
                ),
            errorWidget: (context, url, error) => const ImageErrorPlaceholder(),
          ),
        ),
      ),
    );
  }

  Widget _buildGridThumb(BuildContext context, PostData post, int index) {
    final dragDropService = context.read<PostDragDropService>();
    final isReadOnly = context.read<ProfileFeedProvider>().isReadOnly;

    if (isReadOnly) {
      return GestureDetector(
        onTap: () => _openPost(context, post, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const ImageErrorPlaceholder(),
          ),
        ),
      );
    }

    return LongPressDraggable<PostData>(
      data: post,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        dragDropService.beginDrag(post);
      },
      onDragUpdate: (details) {
        dragDropService.updateDragPosition(details.globalPosition);
      },
      onDragEnd: (details) {
        dragDropService.endDrag();
      },
      feedback: _buildDragFeedbackImage(context, post),
      // 드래그 중에도 원래 셀을 그대로 유지
      childWhenDragging: GestureDetector(
        onTap: () => _openPost(context, post, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const ImageErrorPlaceholder(),
          ),
        ),
      ),
      child: GestureDetector(
        onTap: () => _openPost(context, post, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const ImageErrorPlaceholder(),
          ),
        ),
      ),
    );
  }

  // Draggable feedbacks
  Widget _buildDragFeedbackCard(BuildContext context, PostData post) {
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.95,
        child: Container(
          width: 280,
          height: 180,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 4 / 5,
                child: CachedNetworkImage(
                  imageUrl: post.thumbnailImageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        post.title,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.parsedContent,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragFeedbackImage(BuildContext context, PostData post) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 160,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const ImageErrorPlaceholder(),
          ),
        ),
      ),
    );
  }

  void _openPost(BuildContext context, PostData post, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => PostReaderScreen(
              exported: post.toExportedData(),
              heroTag: null,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}
