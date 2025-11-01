import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/draft_service.dart';

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
    with SingleTickerProviderStateMixin {
  late Map<String, List<DraftData>> _drafts;
  String? _swipingDraftId;
  double _swipeProgress = 0.0;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _slideY;

  // 아래로 스와이프 관련 변수들
  double _verticalDragStartY = 0.0;
  double _verticalDragCurrentY = 0.0;
  bool _isDragging = false;
  bool _isScrolling = false;

  bool _isLoading = true;

  // 스크롤 관련 변수들
  final ScrollController _scrollController = ScrollController();
  double _lastScrollOffset = 0.0;
  bool _showAppBar = true;

  @override
  void initState() {
    super.initState();
    _drafts = {}; // 초기화

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _scale = Tween<double>(
      begin: 0.98,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slideY = Tween<double>(
      begin: 24.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();

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
    _ctrl.dispose();
    super.dispose();
  }

  void _closeWithAnimation() {
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
              onTap: () => _closeWithAnimation(),
              onPanStart: (details) {
                _verticalDragStartY = details.globalPosition.dy;
                _isDragging = true;
                _isScrolling = false;
              },
              onPanUpdate: (details) {
                if (_isDragging && !_isScrolling) {
                  _verticalDragCurrentY = details.globalPosition.dy;
                  final deltaY = _verticalDragCurrentY - _verticalDragStartY;

                  // 아래로 드래그할 때만 반응 (스크롤이 아닌 경우)
                  if (deltaY > 50) {
                    // 50px 이상 드래그해야 시작
                    setState(() {
                      // 드래그 거리에 따라 bouncing 효과
                      final progress = ((deltaY - 50) / 300).clamp(0.0, 1.0);
                      final bounceEffect =
                          1.0 - (progress * 0.4); // 최대 40%까지 줄어듦
                      _ctrl.value = bounceEffect;
                    });
                  }
                }
              },
              onPanEnd: (details) {
                if (_isDragging && !_isScrolling) {
                  final deltaY = _verticalDragCurrentY - _verticalDragStartY;
                  final velocity = details.velocity.pixelsPerSecond.dy;

                  // 아래로 충분히 드래그했거나 빠른 속도로 아래로 스와이프했을 때 닫기
                  if (deltaY > 200 || velocity > 800) {
                    _closeWithAnimation();
                  } else {
                    // 원래 위치로 복원
                    _ctrl.forward();
                  }

                  _isDragging = false;
                }
              },
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withOpacity(0.3)),
              ),
            ),
          ),

          // 임시저장 목록
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 100,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                return Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideY.value),
                    child: Transform.scale(scale: _scale.value, child: child),
                  ),
                );
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // 스크롤 중일 때는 드래그 감지 비활성화
                  if (notification is ScrollStartNotification) {
                    _isScrolling = true;
                  } else if (notification is ScrollEndNotification) {
                    _isScrolling = false;
                  }
                  return false;
                },
                child: GestureDetector(
                  onPanStart: (details) {
                    if (!_isScrolling) {
                      _verticalDragStartY = details.globalPosition.dy;
                      _isDragging = true;
                    }
                  },
                  onPanUpdate: (details) {
                    if (_isDragging && !_isScrolling) {
                      _verticalDragCurrentY = details.globalPosition.dy;
                      final deltaY =
                          _verticalDragCurrentY - _verticalDragStartY;

                      // 아래로 드래그할 때만 반응 (스크롤이 아닌 경우)
                      if (deltaY > 300) {
                        // 300px 이상 드래그해야 시작
                        setState(() {
                          // 드래그 거리에 따라 bouncing 효과
                          final progress = ((deltaY - 300) / 300).clamp(
                            0.0,
                            1.0,
                          );
                          final bounceEffect =
                              1.0 - (progress * 0.4); // 최대 40%까지 줄어듦
                          _ctrl.value = bounceEffect;
                        });
                      }
                    }
                  },
                  onPanEnd: (details) {
                    if (_isDragging && !_isScrolling) {
                      final deltaY =
                          _verticalDragCurrentY - _verticalDragStartY;
                      final velocity = details.velocity.pixelsPerSecond.dy;

                      // 아래로 충분히 드래그했거나 빠른 속도로 아래로 스와이프했을 때 닫기
                      if (deltaY > 200 || velocity > 800) {
                        _closeWithAnimation();
                      } else {
                        // 원래 위치로 복원
                        _ctrl.forward();
                      }

                      _isDragging = false;
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child:
                          _drafts.isEmpty
                              ? _buildEmptyState()
                              : _buildDraftList(),
                    ),
                  ),
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
                  color: Colors.black.withOpacity(0.3),
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    left: 24,
                    right: 24,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _closeWithAnimation(),
                        child: Text(
                          '닫기',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '임시저장',
                            style: TextStyle(
                              color: Colors.white,
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
        '임시저장된 글이 없습니다',
        style: TextStyle(
          color: AppColors.darkTextSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildDraftList() {
    final topPadding =
        MediaQuery.of(context).padding.top + 56 + 32; // SafeArea + 앱바 + 여백

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
      padding: EdgeInsets.only(
        top: topPadding,
        left: 24,
        right: 24,
        bottom: 32,
      ),
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

    // 스와이프 거리 계산
    final double swipeOffset = isSwiping ? _swipeProgress * 80 : 0.0;
    final bool showDeleteButton = isSwiping && _swipeProgress >= 0.8;

    return GestureDetector(
      key: ValueKey('draft_${draft.id}'),
      onTap: () async {
        if (isSwiping) {
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
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        }
      },
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < 0) {
          setState(() {
            _swipingDraftId = draft.id;
            _swipeProgress = (_swipeProgress + (-details.delta.dx / 80)).clamp(
              0.0,
              1.0,
            );
          });
        } else if (details.delta.dx > 0 && isSwiping) {
          setState(() {
            _swipeProgress = (_swipeProgress - (details.delta.dx / 80)).clamp(
              0.0,
              1.0,
            );
            if (_swipeProgress <= 0.1) {
              _swipingDraftId = null;
              _swipeProgress = 0.0;
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_swipeProgress < 0.5) {
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        } else {
          setState(() {
            _swipeProgress = 1.0;
          });
        }
      },
      child: Container(
        height: 72,
        child: Stack(
          children: [
            // 삭제 버튼 배경
            if (isSwiping)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 80,
                child: Container(
                  color: Colors.red.withOpacity(0.1),
                  child: AnimatedOpacity(
                    opacity: showDeleteButton ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: GestureDetector(
                      onTap: () async {
                        setState(() {
                          _swipingDraftId = null;
                          _swipeProgress = 0.0;
                        });

                        final draftService = DraftService();
                        await draftService.deleteDraft(draft.id);
                        _loadDrafts();
                      },
                      child: Center(
                        child: Text(
                          '삭제',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 메인 아이템
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(-swipeOffset, 0),
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
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
