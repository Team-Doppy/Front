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

class _DraftListOverlayState extends State<DraftListOverlay> {
  late Map<String, List<DraftData>> _drafts;
  String? _swipingDraftId;
  double _swipeProgress = 0.0;

  bool _isLoading = true;

  // 스크롤 관련 변수들
  final ScrollController _scrollController = ScrollController();
  double _lastScrollOffset = 0.0;
  bool _showAppBar = true;

  @override
  void initState() {
    super.initState();
    _drafts = {}; // 초기화

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
        return _buildDraftItem(allDrafts[index]);
      },
    );
  }

  Widget _buildDraftItem(DraftData draft) {
    final title = draft.title.isNotEmpty ? draft.title : '무제';
    final isSwiping = _swipingDraftId == draft.id;
    final isCurrentDraft = widget.currentDraftId == draft.id;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final double deleteButtonWidth = 120.0;

    return GestureDetector(
      key: ValueKey('draft_${draft.id}'),
      onTap: () async {
        if (isSwiping) {
          // 스와이프 중이면 닫기
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        } else {
          Navigator.of(context).pop();
          await Future.delayed(const Duration(milliseconds: 100));
          widget.onLoadDraft(draft.id);
        }
      },
      onHorizontalDragStart: (details) {
        if (_swipingDraftId != null && _swipingDraftId != draft.id) {
          // 다른 아이템이 스와이프 중이면 닫기
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        }
      },
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < 0) {
          // 왼쪽으로 스와이프
          setState(() {
            _swipingDraftId = draft.id;
            _swipeProgress = (_swipeProgress +
                    (-details.delta.dx / deleteButtonWidth))
                .clamp(0.0, 1.0);
          });
        } else if (details.delta.dx > 0 && isSwiping) {
          // 오른쪽으로 스와이프 (닫기)
          setState(() {
            _swipeProgress = (_swipeProgress -
                    (details.delta.dx / deleteButtonWidth))
                .clamp(0.0, 1.0);
            if (_swipeProgress <= 0.1) {
              _swipingDraftId = null;
              _swipeProgress = 0.0;
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_swipeProgress < 0.5) {
          // 50% 미만이면 닫기
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        } else {
          // 50% 이상이면 열린 상태 유지
          setState(() {
            _swipeProgress = 1.0;
          });
        }
      },
      child: Container(
        height: 85,
        child: Stack(
          children: [
            // 삭제 버튼 (항상 표시, 스와이프 시 보임)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: deleteButtonWidth,
              child: GestureDetector(
                onTap: () async {
                  // 확인 다이얼로그 표시
                  final confirmed = await DialogUtils.showConfirmDialog(
                    context,
                    title: context.tr('delete_draft_confirm_title'),
                    message: context.tr('delete_draft_confirm_message'),
                    confirmText: context.tr('delete'),
                    cancelText: context.tr('cancel'),
                    isDestructive: true,
                  );

                  if (confirmed == true) {
                    setState(() {
                      _swipingDraftId = null;
                      _swipeProgress = 0.0;
                    });

                    final draftService = DraftService();
                    await draftService.deleteDraft(draft.id);
                    _loadDrafts();
                  }
                },
                child: Container(
                  color: Colors.red.withOpacity(0.15),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 24),
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

            // 메인 아이템
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(-_swipeProgress * deleteButtonWidth, 0),
                child: Container(
                  color:
                      isDarkMode
                          ? Theme.of(context).colorScheme.surface
                          : const ui.Color.fromARGB(255, 240, 240, 240),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color:
                              isCurrentDraft
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
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
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
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
          ],
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
