import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/pages/components/grid_category_section.dart';
import 'package:doppy/pages/components/vertical_category_section.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart'
    show FeedDisplayMode;
import 'package:doppy/providers/feed_provider/profile_feed_sections_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef ProfileSectionMoreTap = void Function(String sectionPhaseKey);

class ProfileFeedSectionsView extends StatefulWidget {
  const ProfileFeedSectionsView({
    super.key,
    required this.sections,
    required this.displayMode,
    required this.isOwnProfile,
    required this.flattenSections,
    required this.mainScrollController,
    required this.onTapMore,
    required this.selectedBase,
    required this.systemCategoryMappings,
  });

  final List<Map<String, dynamic>> sections;
  final FeedDisplayMode displayMode;
  final bool isOwnProfile;
  final bool flattenSections;
  final ScrollController? mainScrollController;
  final ProfileSectionMoreTap onTapMore;
  final BaseFilter selectedBase;
  final Map<String, List<Map<String, dynamic>>>? systemCategoryMappings;

  @override
  State<ProfileFeedSectionsView> createState() =>
      _ProfileFeedSectionsViewState();
}

class _ProfileFeedSectionsViewState extends State<ProfileFeedSectionsView>
    with TickerProviderStateMixin {
  late List<Map<String, dynamic>> _localSections;

  String? _draggingPhaseKey;
  int? _draggingIndex;
  int? _insertIndex;
  Offset? _lastDragGlobalPosition;
  Timer? _autoScrollTimer;

  bool get _isDragging => _draggingPhaseKey != null;

  @override
  void initState() {
    super.initState();
    _localSections = List<Map<String, dynamic>>.from(widget.sections);
  }

  @override
  void didUpdateWidget(covariant ProfileFeedSectionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 드래그 중이 아닐 때만 서버/부모 업데이트를 반영
    if (!_isDragging) {
      _localSections = List<Map<String, dynamic>>.from(widget.sections);
    }
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // BaseFeedProvider를 찾을 수 없을 수 있으므로 try-catch로 처리
    BaseFeedProvider? feedProvider;
    try {
      feedProvider = context.read<BaseFeedProvider>();
    } catch (e) {
      debugPrint('[ProfileFeedSectionsView] BaseFeedProvider를 찾을 수 없음: $e');
    }

    final String? profileImageFromUser =
        feedProvider?.userInfo?['profileImageUrl'] as String?;

    if (_localSections.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // ✅ 곰신(여친) 프로필: 섹션 구분 없이 통짜 타임라인으로 표시
    if (widget.flattenSections) {
      final allPosts = <PostData>[];
      for (final section in _localSections) {
        final rawPosts = section['posts'] as List? ?? const [];
        allPosts.addAll(_mapRawToPosts(rawPosts, profileImageFromUser));
      }

      final orderedPosts = _orderPostsBySystemMappings(allPosts);

      final Widget postSection =
          widget.displayMode == FeedDisplayMode.card
              ? VerticalCategorySection(
                posts: orderedPosts,
                displayMode: widget.displayMode,
                isLastSection: true,
                mainScrollController: widget.mainScrollController,
                isOwnProfile: widget.isOwnProfile,
              )
              : GridCategorySection(
                posts: orderedPosts,
                displayMode: widget.displayMode,
                isLastSection: true,
                mainScrollController: widget.mainScrollController,
                isOwnProfile: widget.isOwnProfile,
              );

      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            postSection,
            SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
          ],
        ),
      );
    }

    // 본인 프로필이고 섹션이 2개 이상일 때만 드래그 앤 드롭 가능
    final canReorder = widget.isOwnProfile && _localSections.length > 1;

    if (canReorder) {
      // ✅ 커스텀 드래그 앤 드롭 (삽입 위치 gap + 엣지 자동 스크롤 + 드래그 중 1줄 표시)
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // gap 슬롯을 항상 렌더링해서 AnimatedSize가 자연스럽게 동작하도록 함
            _buildInsertGap(slotIndex: 0),
            for (int i = 0; i < _localSections.length; i++) ...[
              _buildDraggableSection(
                index: i,
                section: _localSections[i],
                isLast: i == _localSections.length - 1,
                profileImageFromUser: profileImageFromUser,
              ),
              _buildInsertGap(slotIndex: i + 1),
            ],
            // 바텀바 여백
            SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
          ],
        ),
      );
    } else {
      // 일반 Column 사용 (드래그 불가)
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _localSections.length; i++)
              _buildSection(
                context: context,
                section: _localSections[i],
                isLast: i == _localSections.length - 1,
                profileImageFromUser: profileImageFromUser,
              ),
            // 바텀바 여백
            SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
          ],
        ),
      );
    }
  }

  // === Custom section drag/drop ===

  Widget _buildInsertGap({required int slotIndex}) {
    // ✅ gap 자체가 drop 타겟이 되도록 (사이에 드롭했는데 취소되는 문제 방지)
    const targetHeight = 80.0; // 요청: 더 크게
    const baseHitHeight = 24.0; // 드래그 중 최소 hit 영역

    final active = _isDragging && _insertIndex == slotIndex;
    final h = _isDragging ? (active ? targetHeight : baseHitHeight) : 0.0;

    return DragTarget<String>(
      onWillAccept: (data) => _isDragging && data != null,
      onMove: (details) {
        _lastDragGlobalPosition = details.offset;
        final from = _draggingIndex;
        if (from == null) return;

        final shouldIgnore = _isNoopTarget(from: from, to: slotIndex);
        final nextIdx =
            shouldIgnore ? null : slotIndex.clamp(0, _localSections.length);
        if (nextIdx != _insertIndex) {
          setState(() {
            _insertIndex = nextIdx;
          });
        }
      },
      onAccept: (_) async {
        final from = _draggingIndex;
        if (from == null) return;
        final to = slotIndex;

        // ✅ 제자리(no-op)면 아무것도 하지 않음
        if (_isNoopTarget(from: from, to: to)) return;

        final prev = List<Map<String, dynamic>>.from(_localSections);

        // ✅ 새 리스트를 생성하여 순서 변경 (Flutter 변경 감지 보장)
        final newSections = List<Map<String, dynamic>>.from(_localSections);
        final moved = newSections.removeAt(from);
        final insertAt = _finalInsertAt(from: from, to: to);
        newSections.insert(insertAt, moved);

        _stopAutoScroll();
        setState(() {
          _localSections = newSections;
          _draggingPhaseKey = null;
          _draggingIndex = null;
          _insertIndex = null;
          _lastDragGlobalPosition = null;
        });

        try {
          await _commitSectionOrder();
        } catch (e) {
          debugPrint('[ProfileFeedSectionsView] 섹션 순서 저장 실패(롤백): $e');
          setState(() {
            _localSections = prev;
          });
          if (mounted) {
            ErrorHandler.handleError(
              context,
              e,
              customMessage: '섹션 순서 저장에 실패했습니다',
            );
          }
        }
      },
      builder: (context, _, __) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: h,
            child:
                h == 0
                    ? const SizedBox.shrink()
                    : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child:
                          active
                              ? Center(child: Container(height: 4, width: 80))
                              : const SizedBox.expand(),
                    ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required bool showDragHandle,
    bool compact = false,
    bool hasMore = false,
    String? phaseKey,
  }) {
    // ✅ phase: "unspecified" 섹션은 헤더 타이틀 제거 (핸들만 표시)
    final shouldShowTitle = phaseKey != 'unspecified' && title.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (showDragHandle)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          if (shouldShowTitle)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: compact ? 1.1 : null,
                ),
              ),
            ),
          if (hasMore && phaseKey != null && phaseKey.isNotEmpty) ...[
            const Spacer(),
            TextButton(
              onPressed: () => widget.onTapMore(phaseKey),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '더보기',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _startAutoScroll() {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScrollTick(),
    );
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _autoScrollTick() {
    final controller = widget.mainScrollController;
    final pos = _lastDragGlobalPosition;
    if (controller == null || !controller.hasClients || pos == null) return;

    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;

    // ✅ 하단 탭바/세이프에리어 때문에 "화면 아래쪽"에 있어도 dy가 충분히 크지 않아
    // auto-scroll down이 안 되는 케이스가 있어, usable 영역으로 보정한다.
    final topBlocked = mq.padding.top + 56; // 상단 상태바 + 헤더 여유
    final bottomBlocked = mq.padding.bottom + 90; // 하단 홈 인디케이터 + 탭바 여유

    const edge = 120.0; // 엣지 감지 범위(상/하단)
    const maxSpeed = 18.0;

    double delta = 0;
    final topStart = topBlocked + edge;
    final bottomStart = (screenH - bottomBlocked) - edge;

    if (pos.dy < topStart) {
      // 위쪽: 더 깊이 들어갈수록 더 빠르게
      final t = ((topStart - pos.dy) / edge).clamp(0.0, 1.0);
      delta = -maxSpeed * t;
    } else if (pos.dy > bottomStart) {
      // 아래쪽: 더 깊이 들어갈수록 더 빠르게
      final t = ((pos.dy - bottomStart) / edge).clamp(0.0, 1.0);
      delta = maxSpeed * t;
    }

    if (delta == 0) return;
    final next = (controller.offset + delta).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next != controller.offset) {
      controller.jumpTo(next);
    }
  }

  Future<void> _commitSectionOrder() async {
    final phaseOrder =
        _localSections
            .map((s) => (s['phase'] as String? ?? '').toString())
            .where((p) => p.isNotEmpty)
            .toList();
    if (phaseOrder.isEmpty) return;

    // ✅ 실패 시 예외를 상위로 전달 (드롭에서 롤백하기 위함)
    final provider = context.read<ProfileFeedSectionsProvider>();
    await provider.saveSectionOrder(phaseOrder);
  }

  int _calcInsertIndex({
    required int targetIndex,
    required Offset globalPosition,
    required BuildContext targetContext,
  }) {
    final box = targetContext.findRenderObject() as RenderBox?;
    if (box == null) return targetIndex;
    final local = box.globalToLocal(globalPosition);
    final before = local.dy < (box.size.height / 2);
    return before ? targetIndex : targetIndex + 1;
  }

  int _finalInsertAt({required int from, required int to}) {
    var insertAt = to;
    if (insertAt > from) insertAt -= 1;
    return insertAt.clamp(0, _localSections.length);
  }

  bool _isNoopTarget({required int from, required int to}) {
    final finalAt = _finalInsertAt(from: from, to: to);
    // ✅ 제자리(no-op)만 금지. (인접 1칸 이동은 허용)
    return finalAt == from;
  }

  Widget _buildDraggableSection({
    required int index,
    required Map<String, dynamic> section,
    required bool isLast,
    required String? profileImageFromUser,
  }) {
    // ✅ phase가 null이거나 빈 문자열이면 "unspecified"로 처리
    final rawPhase = section['phase'];
    final phaseKey =
        (rawPhase == null || rawPhase.toString().isEmpty)
            ? 'unspecified'
            : rawPhase.toString();
    final title = _sectionTitleFromPhase(phaseKey);

    final rawPosts = section['posts'] as List? ?? const [];
    var posts = _mapRawToPosts(rawPosts, profileImageFromUser);
    posts = _applyAccessFilter(posts);
    final hasMore = section['hasMore'] == true;

    final header = LongPressDraggable<String>(
      data: phaseKey,
      maxSimultaneousDrags: 1,
      onDragStarted: () {
        setState(() {
          _draggingPhaseKey = phaseKey;
          _draggingIndex = index;
          _insertIndex = index;
        });
        _startAutoScroll();
      },
      onDragUpdate: (details) {
        _lastDragGlobalPosition = details.globalPosition;
      },
      // ⚠️ onDragEnd에서 상태를 정리해버리면 DragTarget.onAccept가 못 타는 케이스가 있음
      // (드롭이 "취소"처럼 보임). 완료/취소에서만 정리한다.
      onDragEnd: (_) => _stopAutoScroll(),
      onDragCompleted: () => _stopAutoScroll(),
      onDraggableCanceled: (_, __) {
        _stopAutoScroll();
        setState(() {
          _draggingPhaseKey = null;
          _draggingIndex = null;
          _insertIndex = null;
          _lastDragGlobalPosition = null;
        });
      },
      feedback: Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 32,
            maxWidth: MediaQuery.of(context).size.width - 32,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.08),
              ),
            ),
            child: _buildSectionHeader(
              title: title,
              showDragHandle: true,
              compact: true,
              hasMore: hasMore,
              phaseKey: phaseKey,
            ),
          ),
        ),
      ),
      child: _buildSectionHeader(
        title: title,
        showDragHandle: true,
        hasMore: hasMore,
        phaseKey: phaseKey,
      ),
    );

    final Widget postSection =
        widget.displayMode == FeedDisplayMode.card
            ? VerticalCategorySection(
              posts: posts,
              displayMode: widget.displayMode,
              isLastSection: isLast,
              mainScrollController: widget.mainScrollController,
              isOwnProfile: widget.isOwnProfile,
            )
            : GridCategorySection(
              posts: posts,
              displayMode: widget.displayMode,
              isLastSection: isLast,
              mainScrollController: widget.mainScrollController,
              isOwnProfile: widget.isOwnProfile,
            );

    // ✅ 드래그 중: 배경에서 해당 섹션 숨김 (feedback만 보임)
    final isDraggingMe = _draggingPhaseKey == phaseKey;
    final content =
        isDraggingMe
            ? SizedBox(
              height: 0,
              child: Opacity(
                opacity: 0,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, postSection],
                  ),
                ),
              ),
            )
            : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [header, postSection],
              ),
            );

    // DragTarget의 context가 아이템별로 달라야 midpoint 삽입 계산이 정확해짐
    return Builder(
      builder: (itemContext) {
        return DragTarget<String>(
          onWillAccept: (data) => data != null && data != phaseKey,
          onMove: (details) {
            _lastDragGlobalPosition = details.offset;
            final idx = _calcInsertIndex(
              targetIndex: index,
              globalPosition: details.offset,
              targetContext: itemContext,
            );
            final from = _draggingIndex;
            final shouldIgnore =
                from != null && _isNoopTarget(from: from, to: idx);

            final nextIdx =
                shouldIgnore ? null : idx.clamp(0, _localSections.length);

            if (nextIdx != _insertIndex) {
              setState(() {
                _insertIndex = nextIdx;
              });
            }
          },
          onLeave: (_) {
            // leave 시에는 유지 (엣지 auto-scroll 중 흔들림 방지)
          },
          onAccept: (_) async {
            final from = _draggingIndex;
            final to = _insertIndex;
            if (from == null || to == null) return;

            // ✅ 제자리(no-op)면 아무것도 하지 않음
            if (_isNoopTarget(from: from, to: to)) {
              _stopAutoScroll();
              setState(() {
                _draggingPhaseKey = null;
                _draggingIndex = null;
                _insertIndex = null;
                _lastDragGlobalPosition = null;
              });
              return;
            }

            final prev = List<Map<String, dynamic>>.from(_localSections);
            final moved = _localSections.removeAt(from);
            final insertAt = _finalInsertAt(from: from, to: to);
            _localSections.insert(insertAt, moved);

            _stopAutoScroll();
            setState(() {
              _draggingPhaseKey = null;
              _draggingIndex = null;
              _insertIndex = null;
              _lastDragGlobalPosition = null;
            });

            // 저장 실패 시 롤백
            try {
              await _commitSectionOrder();
            } catch (e) {
              debugPrint('[ProfileFeedSectionsView] 섹션 순서 저장 실패(롤백): $e');
              setState(() {
                _localSections = prev;
              });
              if (mounted) {
                ErrorHandler.handleError(
                  context,
                  e,
                  customMessage: '섹션 순서 저장에 실패했습니다',
                );
              }
            }
          },
          builder: (_, __, ___) => content,
        );
      },
    );
  }

  /// 일반 섹션 빌드 (드래그 불가)
  Widget _buildSection({
    required BuildContext context,
    required Map<String, dynamic> section,
    required bool isLast,
    required String? profileImageFromUser,
  }) {
    // ✅ phase가 null이거나 빈 문자열이면 "unspecified"로 처리
    final rawPhase = section['phase'];
    final phaseKey =
        (rawPhase == null || rawPhase.toString().isEmpty)
            ? 'unspecified'
            : rawPhase.toString();
    final title = _sectionTitleFromPhase(phaseKey);

    final rawPosts = section['posts'] as List? ?? const [];
    var posts = _mapRawToPosts(rawPosts, profileImageFromUser);
    posts = _applyAccessFilter(posts);
    final hasMore = section['hasMore'] == true;

    final Widget postSection =
        widget.displayMode == FeedDisplayMode.card
            ? VerticalCategorySection(
              posts: posts,
              displayMode: widget.displayMode,
              isLastSection: isLast,
              mainScrollController: widget.mainScrollController,
              isOwnProfile: widget.isOwnProfile,
            )
            : GridCategorySection(
              posts: posts,
              displayMode: widget.displayMode,
              isLastSection: isLast,
              mainScrollController: widget.mainScrollController,
              isOwnProfile: widget.isOwnProfile,
            );

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: title,
            showDragHandle: widget.isOwnProfile && _localSections.length > 1,
            hasMore: hasMore,
            phaseKey: phaseKey,
          ),
          postSection,
          // ✅ phase: "unspecified" 섹션은 "더보기" 버튼 표시 안 함
          if (hasMore && phaseKey.isNotEmpty && phaseKey != 'unspecified')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => widget.onTapMore(phaseKey),
                  child: Text('$title 더보기'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<PostData> _applyAccessFilter(List<PostData> posts) {
    if (!widget.isOwnProfile) return posts; // 타인 프로필: 서버에서 이미 필터링됨
    if (widget.selectedBase == BaseFilter.all) return posts;

    final systemKey = SystemCategoryKeys.fromBaseFilter(widget.selectedBase);
    if (systemKey == null || systemKey.isEmpty) return posts;

    final mappings = widget.systemCategoryMappings;
    if (mappings == null) return posts;
    final postIdList = mappings[systemKey];
    if (postIdList == null || postIdList.isEmpty) return <PostData>[];

    // order 순서대로 정렬
    final orderedList =
        (postIdList as List)
            .map((item) {
              if (item is Map<String, dynamic>) {
                return item;
              } else if (item is int) {
                return {'postId': item, 'order': 0};
              }
              return null;
            })
            .whereType<Map<String, dynamic>>()
            .toList();

    orderedList.sort((a, b) {
      final orderA = (a['order'] as num?)?.toInt() ?? 0;
      final orderB = (b['order'] as num?)?.toInt() ?? 0;
      return orderA.compareTo(orderB);
    });

    final orderedPostIds =
        orderedList
            .map((m) => m['postId']?.toString())
            .whereType<String>()
            .toList();

    // postId 순서대로 포스트 정렬
    final postMap = {for (var post in posts) post.id: post};
    return orderedPostIds
        .map((id) => postMap[id])
        .where((post) => post != null)
        .cast<PostData>()
        .toList();
  }

  /// systemCategoryMappings의 order 기준으로 posts를 정렬 (통짜 타임라인용)
  /// - mappings가 없거나 비어있으면 createdAt 최신순 fallback
  List<PostData> _orderPostsBySystemMappings(List<PostData> posts) {
    final systemMappings = widget.systemCategoryMappings;
    if (systemMappings == null || systemMappings.isEmpty) {
      final fallback = List<PostData>.from(posts);
      fallback.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return fallback;
    }

    // feed.dart와 동일한 방식: 모든 key의 (postId, order)를 모아서 order로 정렬
    final allOrderedItems = <Map<String, dynamic>>[];
    for (final entry in systemMappings.entries) {
      final list = entry.value;
      for (final item in list) {
        // 이미 Map<String,dynamic> 형태로 파싱되어 있음 (provider에서)
        allOrderedItems.add(item);
      }
    }

    allOrderedItems.sort((a, b) {
      final orderA = (a['order'] as num?)?.toInt() ?? 0;
      final orderB = (b['order'] as num?)?.toInt() ?? 0;
      return orderA.compareTo(orderB);
    });

    final orderedPostIds =
        allOrderedItems
            .map((m) => m['postId']?.toString())
            .whereType<String>()
            .toList();

    // 실제 존재하는 포스트만 order대로 배치
    final postMap = {for (final p in posts) p.id: p};
    final orderedPosts =
        orderedPostIds.map((id) => postMap[id]).whereType<PostData>().toList();

    // mappings에 없는 포스트는 최신순으로 뒤에 붙임 (방어적)
    if (orderedPosts.length != posts.length) {
      final remain =
          posts.where((p) => !orderedPostIds.contains(p.id)).toList();
      remain.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      orderedPosts.addAll(remain);
    }

    return orderedPosts;
  }

  List<PostData> _mapRawToPosts(List<dynamic> rawList, String? profileImage) {
    return rawList
        .map((raw) {
          try {
            final postData = PostData.fromServer(raw);
            if ((postData.authorProfileImageUrl.isEmpty) &&
                profileImage != null &&
                profileImage.isNotEmpty) {
              return PostData(
                id: postData.id,
                thumbnailImageUrl: postData.thumbnailImageUrl,
                title: postData.title,
                author: postData.author,
                authorId: postData.authorId,
                authorProfileImageUrl: profileImage,
                content: postData.content,
                accessLevel: postData.accessLevel,
                createdAt: postData.createdAt,
                updatedAt: postData.updatedAt,
                viewCount: postData.viewCount,
                likeCount: postData.likeCount,
                commentCount: postData.commentCount,
                isLiked: postData.isLiked,
              );
            }
            return postData;
          } catch (_) {
            return null;
          }
        })
        .whereType<PostData>()
        .toList();
  }

  String _sectionTitleFromPhase(String phaseKey) {
    switch (phaseKey) {
      case 'preEnlistment':
        return '입대전';
      case 'training':
        return '훈련소';
      case 'private':
        return '이병';
      case 'privateFirstClass':
        return '일병';
      case 'corporal':
        return '상병';
      case 'sergeant':
        return '병장';
      case 'leave':
        return '휴가모듬';
      case 'preEnlistmentMemory':
        return '입대전 추억';
      case 'unspecified':
        return ''; // ✅ phase: "unspecified"는 타이틀 없음 (핸들만 표시)
      default:
        return phaseKey;
    }
  }
}
