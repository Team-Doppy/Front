import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/draft_service.dart';

class DraftListOverlay extends StatefulWidget {
  const DraftListOverlay({
    super.key,
    required this.drafts,
    required this.currentDraftId,
    required this.onLoadDraft,
    required this.onDeleteDraft,
  });

  final Map<String, List<DraftData>> drafts;
  final String? currentDraftId;
  final void Function(String draftId) onLoadDraft;
  final Future<void> Function(String draftId) onDeleteDraft;

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
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    // 깊은 복사로 로컬 상태 보관 (UI 반영 위해 직접 수정)
    _drafts = {
      for (final e in widget.drafts.entries)
        e.key: List<DraftData>.from(e.value),
    };
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
  }

  void _closeWithAnimation() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const ui.Color.fromARGB(234, 54, 54, 54),
        elevation: 0,
        leading: IconButton(
          onPressed: () => _closeWithAnimation(),
          icon: Icon(
            Icons.close,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        title: Text(
          '임시저장 목록',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            fontSize: 18,
          ),
        ),
        scrolledUnderElevation: 0,
      ),
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
                  color: const ui.Color.fromARGB(234, 54, 54, 54),
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
    return ListView.builder(
      padding: const EdgeInsets.all(20),
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

    return Dismissible(
      key: ValueKey('draft_${draft.id}'),
      direction: DismissDirection.endToStart, // 오른쪽→왼쪽으로 밀어 삭제
      background: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 0),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete, color: Colors.red.withOpacity(0.9)),
            const SizedBox(width: 8),
            Text('삭제', style: TextStyle(color: Colors.red.withOpacity(0.9))),
          ],
        ),
      ),
      onUpdate: (details) {
        setState(() {
          if (details.direction == DismissDirection.endToStart &&
              details.progress > 0) {
            _swipingDraftId = draft.id;
            _swipeProgress = details.progress;
          } else {
            _swipingDraftId = null;
            _swipeProgress = 0.0;
          }
        });
      },
      confirmDismiss: (direction) async {
        // 일정 거리 넘어가면 바로 삭제. 추가 확인 없음
        return true;
      },
      onDismissed: (direction) async {
        setState(() {
          _swipingDraftId = null;
          _swipeProgress = 0.0;
          // 즉시 로컬에서 제거하여 Dismissible가 트리에서 사라지도록 함
          for (final list in _drafts.values) {
            list.removeWhere((d) => d.id == draft.id);
          }
          _drafts.removeWhere((key, value) => value.isEmpty);
        });
        // 비동기 삭제 및 최신 목록 재동기화(실패해도 UI는 즉시 반영됨)
        try {
          await widget.onDeleteDraft(draft.id);
          final updated = await DraftService().getDraftsByTitle();
          if (!mounted) return;
          setState(() {
            _drafts = {
              for (final e in updated.entries)
                e.key: List<DraftData>.from(e.value),
            };
          });
        } catch (_) {
          // ignore: rethrow or rollback; UI는 이미 제거됨
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 0),
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
          onTap: () {
            widget.onLoadDraft(draft.id);
            Navigator.of(context).pop();
          },
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
