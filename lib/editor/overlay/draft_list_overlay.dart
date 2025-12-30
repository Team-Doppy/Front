import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';

class DraftListOverlay extends StatefulWidget {
  const DraftListOverlay({
    super.key,
    required this.currentDraftId,
    required this.onLoadDraft,
  });

  final String? currentDraftId;
  final void Function(String draftId) onLoadDraft;

  @override
  State<DraftListOverlay> createState() => _DraftListOverlayState();
}

class _DraftListOverlayState extends State<DraftListOverlay>
    with TickerProviderStateMixin {
  late Map<String, List<DraftData>> _drafts;
  String? _swipingDraftId;
  late final AnimationController _swipeController;
  final Set<String> _removingDraftIds = <String>{};

  bool _isLoading = true;

  // 스크롤 관련 변수들
  final ScrollController _scrollController = ScrollController();
  double _lastScrollOffset = 0.0;
  bool _showAppBar = true;

  @override
  void initState() {
    super.initState();
    _drafts = {}; // 초기화
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..value = 0.0;

    // 깊은 복사로 로컬 상태 보관 (UI 반영 위해 직접 수정)
    _loadDrafts();

    // 스크롤 리스너 추가
    _scrollController.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;

    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // 스크롤할 내용이 없으면 (maxScrollExtent가 0이면) 항상 앱바 표시
    if (maxScroll <= 0) {
      if (!_showAppBar) {
        setState(() => _showAppBar = true);
      }
      return;
    }

    final delta = currentOffset - _lastScrollOffset;

    // 스크롤 임계값 (5px 이상 움직여야 반응)
    if (delta.abs() > 5.0) {
      if (delta < 0) {
        // 위로 스크롤 - 앱바 보이기
        if (!_showAppBar) {
          setState(() => _showAppBar = true);
        }
      } else {
        // 아래로 스크롤 - 앱바 숨기기
        if (_showAppBar && currentOffset > 20) {
          setState(() => _showAppBar = false);
        }
      }
    }

    // 맨 위에 있으면 항상 앱바 표시
    if (currentOffset <= 10) {
      if (!_showAppBar) {
        setState(() => _showAppBar = true);
      }
    }

    _lastScrollOffset = currentOffset;
  }

  @override
  void dispose() {
    _swipeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Future<void> _loadDrafts() async {
    final drafts = await DraftService().getDraftsByTitle();
    if (mounted) {
      setState(() {
        _drafts = {
          for (final e in drafts.entries) e.key: List<DraftData>.from(e.value),
        };
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 배경 블러 + 반투명
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _close(),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color:
                      isDarkMode
                          ? const ui.Color.fromARGB(235, 45, 45, 45)
                          : const ui.Color.fromARGB(235, 255, 255, 255),
                ),
              ),
            ),
          ),

          // 임시저장 목록
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 10,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child:
                      _drafts.isEmpty ? _buildEmptyState() : _buildDraftList(),
                ),
              ),
            ),
          ),

          // 블러 연속 앱바
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            top: _showAppBar ? 0 : -100,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 56 + MediaQuery.of(context).padding.top,
                  color:
                      isDarkMode
                          ? const ui.Color.fromARGB(243, 43, 43, 43)
                          : const ui.Color.fromARGB(243, 255, 255, 255),
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    left: 24,
                    right: 24,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _close(),
                        child: Text(
                          context.tr('close'),
                          style: TextStyle(
                            color:
                                isDarkMode
                                    ? Colors.white.withOpacity(0.8)
                                    : Colors.black.withOpacity(0.8),
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            context.tr('drafts'),
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 32), // 닫기 버튼과 균형 맞추기
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        context.tr('no_drafts'),
        style: TextStyle(
          color: AppColors.darkTextSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildDraftList() {
    final topPadding = 70.0; // SafeArea + 앱바 + 여백

    // 제목별로 그룹화된 임시저장을 단순 리스트로 변환
    final allDrafts = <DraftData>[];
    for (final drafts in _drafts.values) {
      if (drafts.isNotEmpty) {
        // 각 제목별로 가장 최근 것만 표시
        allDrafts.add(drafts.first);
      }
    }

    // 최근 수정 순으로 정렬
    allDrafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.only(top: topPadding, left: 24, right: 24),
      itemCount: allDrafts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 1),
      itemBuilder: (context, index) {
        final draft = allDrafts[index];
        if (_removingDraftIds.contains(draft.id)) {
          // 삭제 애니메이션 중인 아이템은 유지하되, 내부에서 shrink 처리
          return _buildDraftItem(draft);
        }
        return _buildDraftItem(draft);
      },
    );
  }

  Widget _buildDraftItem(DraftData draft) {
    final title = draft.title.isNotEmpty ? draft.title : '무제';
    final isSwiping = _swipingDraftId == draft.id;
    final isCurrentDraft = widget.currentDraftId == draft.id;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final double deleteButtonWidth = 120.0;
    // ✅ 스와이프 애니메이션은 controller 기반 (drag 중에도 부드럽게)
    // 주의: AnimatedBuilder 안에서는 반드시 controller.value를 직접 읽어야 한다.
    // (빌드 시점에 계산한 값을 캡처하면 애니메이션이 멈춘 것처럼 보일 수 있음)
    final bool isRemoving = _removingDraftIds.contains(draft.id);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        opacity: isRemoving ? 0.0 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: isRemoving ? 0 : 85,
          child:
              isRemoving
                  ? const SizedBox.shrink()
                  : SizedBox(
                    key: ValueKey('draft_${draft.id}'),
                    child: SizedBox(
                      height: 85,
                      child: Stack(
                        children: [
                          // 삭제 버튼 (스와이프 진행도에 따라 자연스럽게 나타남)
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            width: deleteButtonWidth,
                            child: AnimatedBuilder(
                              animation: _swipeController,
                              builder: (context, child) {
                                final t = (isSwiping
                                        ? _swipeController.value
                                        : 0.0)
                                    .clamp(0.0, 1.0);
                                final eased = Curves.easeOutCubic.transform(t);
                                final opacity = (eased * 1.15).clamp(0.0, 1.0);
                                final scale = ui.lerpDouble(0.92, 1.0, eased)!;
                                return IgnorePointer(
                                  ignoring: opacity < 0.85,
                                  child: Opacity(
                                    opacity: opacity,
                                    child: Transform.scale(
                                      scale: scale,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: InkWell(
                                onTap: () async {
                                  // 확인 다이얼로그 표시
                                  final confirmed =
                                      await DialogUtils.showConfirmDialog(
                                        context,
                                        title: context.tr(
                                          'delete_draft_confirm_title',
                                        ),
                                        message: context.tr(
                                          'delete_draft_confirm_message',
                                        ),
                                        confirmText: context.tr('delete'),
                                        cancelText: context.tr('cancel'),
                                        isDestructive: true,
                                      );

                                  // ✅ 취소/바깥탭이면 스와이프 원복
                                  if (confirmed != true) {
                                    if (_swipingDraftId == draft.id) {
                                      _swipeController.animateTo(
                                        0.0,
                                        curve: Curves.easeOutCubic,
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                      );
                                      setState(() => _swipingDraftId = null);
                                    }
                                    return;
                                  }

                                  if (confirmed == true) {
                                    // UI에서 먼저 닫고(스와이프), 부드럽게 제거 애니메이션
                                    setState(() {
                                      _swipingDraftId = null;
                                      _swipeController.value = 0.0;
                                      _removingDraftIds.add(draft.id);
                                    });

                                    await Future.delayed(
                                      const Duration(milliseconds: 240),
                                    );

                                    final draftService = DraftService();
                                    final ok = await draftService.deleteDraft(
                                      draft.id,
                                    );
                                    if (!mounted) return;

                                    if (!ok) {
                                      // 실패 시 다시 표시
                                      setState(() {
                                        _removingDraftIds.remove(draft.id);
                                      });
                                      return;
                                    }

                                    await _loadDrafts();
                                    if (!mounted) return;
                                    setState(() {
                                      _removingDraftIds.remove(draft.id);
                                    });
                                  }
                                },
                                child: Container(
                                  color: Colors.red.withOpacity(0.10),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 24,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          context.tr('delete'),
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 메인 아이템
                          Positioned.fill(
                            child: GestureDetector(
                              // ✅ 탭/스와이프는 메인 카드에서만 처리해서,
                              // 삭제 버튼 탭이 불러오기(onTap)로 먹히는 문제를 방지한다.
                              onTap: () async {
                                if (isSwiping) {
                                  _swipeController.animateTo(
                                    0.0,
                                    curve: Curves.easeOutCubic,
                                    duration: const Duration(milliseconds: 220),
                                  );
                                  setState(() => _swipingDraftId = null);
                                  return;
                                }
                                Navigator.of(context).pop();
                                await Future.delayed(
                                  const Duration(milliseconds: 100),
                                );
                                widget.onLoadDraft(draft.id);
                              },
                              onHorizontalDragStart: (_) {
                                if (_swipingDraftId != null &&
                                    _swipingDraftId != draft.id) {
                                  _swipeController.value = 0.0;
                                  setState(() => _swipingDraftId = null);
                                }
                                if (_swipingDraftId != draft.id) {
                                  setState(() => _swipingDraftId = draft.id);
                                  _swipeController.value = 0.0;
                                }
                              },
                              onHorizontalDragUpdate: (details) {
                                if (_swipingDraftId != draft.id) return;
                                if (details.delta.dx < 0) {
                                  // 🎯 스와이프 감도 향상: 더 빠르게 반응하도록 배율 증가
                                  final sensitivity = 1.5; // 감도 배율
                                  final next = (_swipeController.value +
                                          (-details.delta.dx /
                                              deleteButtonWidth *
                                              sensitivity))
                                      .clamp(0.0, 1.0);
                                  _swipeController.value = next;
                                } else if (details.delta.dx > 0) {
                                  final sensitivity = 1.5;
                                  final next = (_swipeController.value -
                                          (details.delta.dx /
                                              deleteButtonWidth *
                                              sensitivity))
                                      .clamp(0.0, 1.0);
                                  _swipeController.value = next;
                                  // 🎯 원래대로 돌릴 때 더 적게 밀어도 닫히도록 임계값 상향
                                  if (_swipeController.value <= 0.08) {
                                    _swipeController.value = 0.0;
                                    setState(() => _swipingDraftId = null);
                                  }
                                }
                              },
                              onHorizontalDragEnd: (details) {
                                if (_swipingDraftId != draft.id) return;
                                final vx = details.velocity.pixelsPerSecond.dx;
                                // 🎯 원래대로 돌릴 때 더 적게 밀어도 되도록 임계값 낮춤
                                final shouldOpen =
                                    (vx < -100) ||
                                    _swipeController.value > 0.08;
                                final target = shouldOpen ? 1.0 : 0.0;
                                _swipeController.animateTo(
                                  target,
                                  curve: Curves.easeOutCubic,
                                  duration: const Duration(milliseconds: 260),
                                );
                                if (!shouldOpen) {
                                  setState(() => _swipingDraftId = null);
                                }
                              },
                              child: AnimatedBuilder(
                                animation: _swipeController,
                                builder: (context, child) {
                                  final t = (isSwiping
                                          ? _swipeController.value
                                          : 0.0)
                                      .clamp(0.0, 1.0);
                                  final eased = Curves.easeOutCubic.transform(
                                    t,
                                  );
                                  return Transform.translate(
                                    offset: Offset(
                                      -eased * deleteButtonWidth,
                                      0,
                                    ),
                                    child: child,
                                  );
                                },
                                child: Container(
                                  color:
                                      isDarkMode
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.surface
                                          : const ui.Color.fromARGB(
                                            255,
                                            240,
                                            240,
                                            240,
                                          ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          color:
                                              isCurrentDraft
                                                  ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                  : Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                          fontSize: 16,
                                          fontWeight:
                                              isCurrentDraft
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDateTime(draft.updatedAt),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }
}
