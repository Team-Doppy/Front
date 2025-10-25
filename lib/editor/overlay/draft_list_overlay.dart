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
                child: Container(
                  color: const ui.Color.fromARGB(234, 28, 28, 28),
                ),
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

          // 애니메이션 앱바 (맨 위로 이동)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            top: _showAppBar ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              height: 56 + MediaQuery.of(context).padding.top,
              decoration: BoxDecoration(
                color: const ui.Color.fromARGB(234, 28, 28, 28),
              ),
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _closeWithAnimation(),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '임시저장 목록',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8),
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            color: AppColors.darkTextSecondary.withOpacity(0.5),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            '임시저장된 글이 없습니다',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftList() {
    final topPadding =
        MediaQuery.of(context).padding.top + 56 + 20; // SafeArea + 앱바 + 여백

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: topPadding,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      itemCount: _drafts.length,
      itemBuilder: (context, index) {
        final title = _drafts.keys.elementAt(index);
        final drafts = _drafts[title]!;
        return _buildDraftGroup(title, drafts);
      },
    );
  }

  Widget _buildDraftGroup(String title, List<DraftData> drafts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 헤더
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${drafts.length}개 버전',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
          ),

          // 버전 목록
          ...drafts.map((draft) => _buildDraftItem(draft)).toList(),
        ],
      ),
    );
  }

  Widget _buildDraftItem(DraftData draft) {
    final title = draft.title.isNotEmpty ? draft.title : '무제';
    final isSwiping = _swipingDraftId == draft.id;

    // 스와이프 거리 계산 (30%까지만 밀림, 그 이후는 고정)
    final double swipeOffset =
        isSwiping
            ? (_swipeProgress < 0.3 ? _swipeProgress : 0.3) *
                MediaQuery.of(context).size.width
            : 0.0;

    final bool showDeleteButton = isSwiping && _swipeProgress >= 0.3;

    return GestureDetector(
      key: ValueKey('draft_${draft.id}'),
      // 다른 곳 터치 시 원위치
      onTap: () async {
        if (isSwiping) {
          // 스와이프 중이면 원위치로 복귀
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        } else {
          // 스와이프 중이 아니면 Draft 로드
          Navigator.of(context).pop();
          await Future.delayed(const Duration(milliseconds: 100));
          widget.onLoadDraft(draft.id);
        }
      },
      onHorizontalDragStart: (details) {
        // 다른 아이템이 열려있으면 먼저 닫기
        if (_swipingDraftId != null && _swipingDraftId != draft.id) {
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        }
      },
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < 0) {
          // 왼쪽으로 드래그
          setState(() {
            _swipingDraftId = draft.id;
            final screenWidth = MediaQuery.of(context).size.width;
            final currentSwipe = swipeOffset - details.delta.dx;
            _swipeProgress = (currentSwipe / screenWidth).clamp(0.0, 0.3);
          });
        } else if (details.delta.dx > 0 && isSwiping) {
          // 오른쪽으로 드래그 (되돌리기)
          setState(() {
            final screenWidth = MediaQuery.of(context).size.width;
            final currentSwipe = swipeOffset - details.delta.dx;
            _swipeProgress = (currentSwipe / screenWidth).clamp(0.0, 0.3);

            if (_swipeProgress <= 0.05) {
              _swipingDraftId = null;
              _swipeProgress = 0.0;
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_swipeProgress < 0.15) {
          // 15% 미만이면 원위치
          setState(() {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          });
        } else if (_swipeProgress >= 0.15 && _swipeProgress < 0.3) {
          // 15~30% 사이면 30%로 스냅
          setState(() {
            _swipeProgress = 0.3;
          });
        }
        // 30% 이상이면 그대로 유지 (버튼 고정)
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 80, // 명시적인 높이 지정
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 배경 (삭제 버튼)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: AnimatedScale(
                  scale: showDeleteButton ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.elasticOut,
                  child: GestureDetector(
                    onTap: () async {
                      // 삭제 버튼 클릭 시
                      setState(() {
                        _swipingDraftId = null;
                        _swipeProgress = 0.0;
                        for (final list in _drafts.values) {
                          list.removeWhere((d) => d.id == draft.id);
                        }
                        _drafts.removeWhere((key, value) => value.isEmpty);
                      });

                      final draftService = DraftService();
                      await draftService.deleteDraft(draft.id);
                      final updated = await draftService.getDraftsByTitle();
                      if (!mounted) return;
                      setState(() {
                        _drafts = {
                          for (final e in updated.entries)
                            e.key: List<DraftData>.from(e.value),
                        };
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '삭제',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 드래프트 아이템 (위로 슬라이드)
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(-swipeOffset, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder.withOpacity(0.3),
                    borderRadius:
                        (_swipingDraftId == draft.id && _swipeProgress > 0.0)
                            ? const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                              topRight: Radius.circular(0),
                              bottomRight: Radius.circular(0),
                            )
                            : BorderRadius.circular(8),
                    border:
                        widget.currentDraftId == draft.id
                            ? Border.all(color: AppColors.primary, width: 2)
                            : null,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '저장: ${_formatDateTime(draft.updatedAt)}',
                      style: const TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                    // 오른쪽 끝에 스와이프 힌트 핸들
                    trailing: Container(
                      width: 16,
                      height: 28,
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
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
