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
  });

  final String sectionTitle;
  final List<PostData> items;
  final Widget Function(BuildContext context, PostData post, int index)
  itemBuilder;
  final int crossAxisCount;
  final double spacing;
  final double aspectRatio;
  final bool readOnly;

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
                dragSvc.setDropTarget(widget.sectionTitle);
                dragSvc.setReorderTargetIndex(idx);
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

                  // 드래그가 다른 섹션을 타겟할 때, 이 섹션에서 드래그된 카드를 임시로 제외해
                  // 자연스럽게 좌측으로 밀리도록 처리
                  List<PostData> effectiveItems = _items;
                  if (svc.isDragging &&
                      svc.draggedPost != null &&
                      svc.targetCategory != null &&
                      svc.targetCategory != widget.sectionTitle) {
                    final draggedId = svc.draggedPost!.id;
                    if (_items.any((p) => p.id == draggedId)) {
                      effectiveItems = _items
                          .where((p) => p.id != draggedId)
                          .toList(growable: false);
                    }
                  }

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
                          children.add(
                            RepaintBoundary(
                              child: SizedBox(
                                key: ValueKey('cell-${post.id}'),
                                width: cellWidth,
                                height: cellHeight,
                                child: widget.itemBuilder(
                                  context,
                                  post,
                                  dataIndex,
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
