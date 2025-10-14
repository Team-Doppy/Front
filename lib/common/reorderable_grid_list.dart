import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/feed_service.dart';

typedef PostAcceptCallback = void Function(PostData post, int targetIndex);

class ReorderableGridList extends StatefulWidget {
  const ReorderableGridList({
    super.key,
    required this.sectionTitle,
    required this.items,
    required this.itemBuilder,
    this.crossAxisCount = 3,
    this.spacing = 6.0,
    this.aspectRatio = 4 / 5,
    this.readOnly = false,
    this.onAccept,
    this.scrollController,
  });

  final String sectionTitle;
  final List<PostData> items;
  final Widget Function(BuildContext context, PostData post, int index)
  itemBuilder;
  final int crossAxisCount;
  final double spacing;
  final double aspectRatio;
  final bool readOnly;
  final ScrollController? scrollController;

  // 드랍 수신 시 부모에 알림 (동일 섹션 재정렬/외부에서 삽입 포함)
  final PostAcceptCallback? onAccept;

  @override
  State<ReorderableGridList> createState() => _ReorderableGridListState();
}

class _ReorderableGridListState extends State<ReorderableGridList> {
  final GlobalKey _gridKey = GlobalKey();
  late List<PostData> _items;

  @override
  void initState() {
    super.initState();
    _items = List<PostData>.from(widget.items);
  }

  @override
  void didUpdateWidget(covariant ReorderableGridList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 아이템 변경 시 내부 리스트 동기화 (길이/아이디가 달라지면 업데이트)
    if (oldWidget.items.length != widget.items.length ||
        !_isSameIds(oldWidget.items, widget.items)) {
      _items = List<PostData>.from(widget.items);
    }
  }

  bool _isSameIds(List<PostData> a, List<PostData> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dragSvc = context.read<PostDragDropService>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cellWidth =
            (constraints.maxWidth -
                widget.spacing * (widget.crossAxisCount - 1)) /
            widget.crossAxisCount;
        // height = width / (width/height)
        final double cellHeight = cellWidth / widget.aspectRatio;

        return Container(
          key: _gridKey,
          child: DragTarget<PostData>(
            onWillAccept: (data) {
              if (widget.readOnly || data == null) return false;
              dragSvc.setDropTarget(widget.sectionTitle);
              return true;
            },
            onMove: (details) {
              if (widget.readOnly) return;
              try {
                final box =
                    _gridKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(details.offset);
                // 전역 자동 스크롤 트리거는 서비스가 담당하므로, 글로벌 포인터 위치만 꾸준히 업데이트
                dragSvc.setDropTarget(widget.sectionTitle);
                dragSvc.updateDragPosition(details.offset);

                // 자동 스크롤 억제 래치가 켜져 있으면 그리드 내 재배치 인식 중단
                if (dragSvc.suppressReorder) {
                  dragSvc.setReorderTargetIndex(null);
                } else {
                  // 그리드 셀 인덱스 계산 및 타겟 인덱스 갱신
                  final double x = local.dx.clamp(0.0, constraints.maxWidth);
                  final double y = local.dy.clamp(0.0, double.infinity);
                  final int col = (x / (cellWidth + widget.spacing))
                      .floor()
                      .clamp(0, widget.crossAxisCount - 1);
                  final int row = (y / (cellHeight + widget.spacing)).floor();
                  final int idx = (row * widget.crossAxisCount + col).clamp(
                    0,
                    _items.length,
                  );
                  dragSvc.setReorderTargetIndex(idx);
                }

                // 세로 자동 스크롤은 전역 DragDropService가 관리 → 중복 방지 위해 여기서는 수행하지 않음
              } catch (_) {}
            },
            onLeave: (_) {
              dragSvc.setReorderTargetIndex(null);
            },
            onAccept: (data) {
              if (widget.readOnly) return;
              final int targetIndex = (dragSvc.reorderTargetIndex ?? 0).clamp(
                0,
                _items.length,
              );

              // 내부 리스트에 즉시 반영 (동일 섹션 재정렬 / 외부에서 삽입)
              final curIdx = _items.indexWhere((p) => p.id == data.id);
              if (curIdx == -1) {
                _items.insert(targetIndex, data);
              } else {
                if (!(targetIndex == curIdx || targetIndex == curIdx + 1)) {
                  _items.removeAt(curIdx);
                  _items.insert(
                    targetIndex > curIdx ? targetIndex - 1 : targetIndex,
                    data,
                  );
                }
              }
              setState(() {});

              // 부모 콜백으로 영속화/외부 이동 처리 위임
              widget.onAccept?.call(data, targetIndex);

              dragSvc.setReorderTargetIndex(null);
              // 드롭 완료: 드래그 상태 해제하여 마스킹 제거
              dragSvc.endDrag();
            },
            builder: (context, candidate, rejected) {
              return Consumer<PostDragDropService>(
                builder: (context, svc, _) {
                  int? insertIndex =
                      (svc.isDragging &&
                              svc.targetCategory == widget.sectionTitle)
                          ? svc.reorderTargetIndex
                          : null;

                  if (svc.isDragging &&
                      svc.targetCategory == widget.sectionTitle &&
                      insertIndex != null &&
                      svc.draggedPost != null) {
                    final curIdx = _items.indexWhere(
                      (p) => p.id == svc.draggedPost!.id,
                    );
                    if (curIdx != -1 &&
                        (insertIndex == curIdx || insertIndex == curIdx + 1)) {
                      insertIndex = null;
                    }
                  }

                  // 항상 원본 셀을 유지한다 (다른 섹션을 타겟해도 소스 섹션에서 사라지지 않음)
                  List<PostData> effectiveItems = _items;

                  // Grid처럼 보이는 ListView (행 단위 생성)
                  final totalCount =
                      effectiveItems.length + ((insertIndex != null) ? 1 : 0);
                  final rowCount =
                      (totalCount + widget.crossAxisCount - 1) ~/
                      widget.crossAxisCount;

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: rowCount,
                    itemBuilder: (context, row) {
                      final children = <Widget>[];
                      for (int col = 0; col < widget.crossAxisCount; col++) {
                        final virtualIndex = row * widget.crossAxisCount + col;
                        if (insertIndex != null &&
                            virtualIndex == insertIndex) {
                          children.add(
                            IgnorePointer(
                              child: AnimatedContainer(
                                key: ValueKey('ph-$virtualIndex'),
                                duration: const Duration(milliseconds: 120),
                                curve: Curves.easeOut,
                                width: cellWidth,
                                height: cellHeight,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.06),
                                ),
                              ),
                            ),
                          );
                          continue;
                        }

                        final dataIndex =
                            (insertIndex != null && virtualIndex > insertIndex)
                                ? virtualIndex - 1
                                : virtualIndex;
                        if (dataIndex >= effectiveItems.length) {
                          children.add(
                            SizedBox(width: cellWidth, height: cellHeight),
                          );
                        } else {
                          final post = effectiveItems[dataIndex];
                          final shouldDim =
                              (svc.isDragging &&
                                  svc.draggedPost?.id == post.id);

                          children.add(
                            RepaintBoundary(
                              child: SizedBox(
                                key: ValueKey('cell-${post.id}'),
                                width: cellWidth,
                                height: cellHeight,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: widget.itemBuilder(
                                        context,
                                        post,
                                        dataIndex,
                                      ),
                                    ),
                                    if (shouldDim)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Container(
                                              color: Colors.black.withOpacity(
                                                0.6,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      }

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: row == rowCount - 1 ? 0 : widget.spacing,
                        ),
                        child: Row(
                          key: ValueKey(
                            'row-$row-${effectiveItems.length}-${insertIndex ?? -1}',
                          ),
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: _padWithSpacing(children, widget.spacing),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _padWithSpacing(List<Widget> tiles, double spacing) {
    final List<Widget> out = [];
    for (int i = 0; i < tiles.length; i++) {
      out.add(tiles[i]);
      if (i != tiles.length - 1) out.add(SizedBox(width: spacing));
    }
    return out;
  }
}
