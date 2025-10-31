import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/post_reader_stickers.dart';
import 'package:doppy/theme/app_colors.dart';

class StickerCanvas extends StatelessWidget {
  final ScrollController scrollController;
  StickerCanvas({super.key, required this.scrollController});
  // 인스턴스별 고유 키로 변경하여 GlobalKey 중복 방지
  final GlobalKey _stackKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: AnimatedBuilder(
        animation: scrollController,
        builder: (context, _) {
          return Consumer<StickerService>(
            builder: (context, svc, __) {
              final ordered = [...svc.stickers]
                ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
              return Stack(
                key: _stackKey,
                children: [
                  if (context.select<StickerService, String?>(
                        (s) => s.selectedId,
                      ) !=
                      null)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap:
                            () => context.read<StickerService>().select(null),
                      ),
                    ),
                  for (final s in ordered)
                    _StickerView(
                      key: ValueKey<String>(s.id),
                      sticker: s,
                      scrollController: scrollController,
                      stackKey: _stackKey,
                    ),

                  // 드래그 프리뷰 오버레이 비활성화 (삭제 판정은 onScaleUpdate에서 직접 수행)

                  // 하단 중앙 휴지통: 어떤 스티커든 드래그 중이면 노출
                  if (context.select<StickerService, bool>(
                    (svc) => svc.isDragging,
                  ))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0, // 툴바에 가리지 않으면서 조금 더 아래 배치
                      child: _TrashBin(stackKey: _stackKey),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TrashBin extends StatefulWidget {
  final GlobalKey stackKey;
  const _TrashBin({required this.stackKey});
  @override
  State<_TrashBin> createState() => _TrashBinState();
}

class _TrashBinState extends State<_TrashBin> {
  static Rect? _rect;

  static bool isOverTrashLocal(BuildContext context, Offset localPos) {
    final r = _rect;
    if (r == null) return false;
    // 원형 + 박스 혼합 판정: 먼저 둥근 박스 확장으로 커버, 추가로 원형 반경으로 보강
    final expanded = r.inflate(36);
    if (expanded.contains(localPos)) return true;
    final center = r.center;
    final double radius = (r.width / 2) + 30;
    return (localPos - center).distance <= radius;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<StickerService>();
    return Center(
      child: _Measure(
        onUpdate: (size, globalTopLeft) {
          // 실제 렌더된 휴지통 위젯의 글로벌 좌표를 Stack 로컬로 변환하여 영역 기록
          final RenderBox? stackBox =
              widget.stackKey.currentContext?.findRenderObject() as RenderBox?;
          if (stackBox != null) {
            final Offset topLeftInStack = stackBox.globalToLocal(globalTopLeft);
            _rect = topLeftInStack & size;
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          width: svc.dragOverDelete ? 72 : 56,
          height: svc.dragOverDelete ? 72 : 56,
          decoration: BoxDecoration(
            color:
                svc.dragOverDelete
                    ? Colors.redAccent.withOpacity(0.9)
                    : AppColors.darkSurface.withOpacity(0.6),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color:
                    svc.dragOverDelete
                        ? Colors.redAccent.withOpacity(0.5)
                        : Colors.black.withOpacity(0.25),
                blurRadius: svc.dragOverDelete ? 18 : 12,
                spreadRadius: 1,
              ),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(
            svc.dragOverDelete ? Icons.delete_forever : Icons.delete_outline,
            color: Colors.white,
            size: svc.dragOverDelete ? 34 : 28,
          ),
        ),
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  final Widget child;
  final void Function(Size size, Offset globalTopLeft) onUpdate;
  const _Measure({required this.child, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final topLeft = box.localToGlobal(Offset.zero);
            onUpdate(box.size, topLeft);
          }
        });
        return child;
      },
    );
  }
}

class _StickerView extends StatefulWidget {
  final Sticker sticker;
  final ScrollController scrollController;
  final GlobalKey stackKey;
  const _StickerView({
    super.key,
    required this.sticker,
    required this.scrollController,
    required this.stackKey,
  });

  @override
  State<_StickerView> createState() => _StickerViewState();
}

class _StickerViewState extends State<_StickerView> {
  Offset _lastFocalPoint = Offset.zero;
  bool _pressing = false;
  Size _stickerSize = const Size(140, 140);
  // 롱프레스 중 핀치 스케일 시작 기준 스케일
  double _pinchStartScale = 1.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _StickerView oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<StickerService>();
    final selected = context.select<StickerService, bool>(
      (s) => s.selectedId == widget.sticker.id,
    );
    final double scrollY =
        widget.scrollController.hasClients
            ? widget.scrollController.offset
            : 0.0;
    final isDragging = context.select<StickerService, bool>(
      (s) => s.isDraggingSticker(widget.sticker.id),
    );
    final pos =
        isDragging
            ? context.select<StickerService, Offset>((s) => s.dragPreviewPos)
            : widget.sticker.position;
    final scale =
        isDragging
            ? context.select<StickerService, double>((s) => s.dragPreviewScale)
            : widget.sticker.scale;
    final rot =
        isDragging
            ? context.select<StickerService, double>(
              (s) => s.dragPreviewRotation,
            )
            : widget.sticker.rotation;

    return Positioned(
      left: pos.dx,
      top: pos.dy - scrollY,
      child: Stack(
        children: [
          // 시각 렌더만, 포인터 완전 통과
          IgnorePointer(
            ignoring: true,
            child: RepaintBoundary(
              child: Transform(
                transform:
                    Matrix4.identity()
                      ..rotateZ(rot)
                      ..scale(scale),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: widget.sticker.opacity,
                  child: _Measure(
                    onUpdate: (size, _global) {
                      _stickerSize = size;
                    },
                    child: _buildStickerBody(
                      selected: selected,
                      isDragging: isDragging,
                      pressing: _pressing,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 확장 롱프레스 존: 스티커 주변 여유(24px) 포함
          Builder(
            builder: (context) {
              const double grabPadding = 24.0;
              final double zoneW = _stickerSize.width + grabPadding * 2;
              final double zoneH = _stickerSize.height + grabPadding * 2;
              return Positioned(
                left: -grabPadding,
                top: -grabPadding,
                width: zoneW,
                height: zoneH,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPressStart: (details) {
                    _lastFocalPoint = details.globalPosition;
                    setState(() => _pressing = true);
                    svc.beginDrag(widget.sticker.id);
                    svc.bringToFront(widget.sticker.id);
                    _pinchStartScale = widget.sticker.scale;
                  },
                  onLongPressMoveUpdate: (details) {
                    try {
                      final delta = details.globalPosition - _lastFocalPoint;
                      _lastFocalPoint = details.globalPosition;

                      final double scrollY =
                          widget.scrollController.hasClients
                              ? widget.scrollController.offset
                              : 0.0;
                      final Size vs = MediaQuery.of(context).size;

                      final Offset cur =
                          context.read<StickerService>().dragPreviewPos;
                      final Offset want = cur + delta;

                      final double baseW = _stickerSize.width;
                      final double baseH = _stickerSize.height;

                      final RenderBox? stackBox =
                          widget.stackKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      final double viewportW = (stackBox?.size.width ??
                              vs.width)
                          .clamp(1.0, double.infinity);

                      final double wantCenterX = want.dx + baseW / 2;
                      final double wantCenterY = want.dy + baseH / 2;

                      final double clampedCenterX = wantCenterX.clamp(
                        baseW / 2,
                        math.max(baseW / 2, viewportW - baseW / 2),
                      );
                      final double clampedCenterY = wantCenterY.clamp(
                        scrollY + baseH / 2,
                        double.infinity,
                      );

                      final double finalX = clampedCenterX - baseW / 2;
                      final double finalY = clampedCenterY - baseH / 2;
                      final Offset clampedDelta = Offset(
                        finalX - cur.dx,
                        finalY - cur.dy,
                      );

                      final Offset centerLocal = Offset(
                        finalX + baseW / 2,
                        finalY - scrollY + baseH / 2,
                      );
                      final bool overTrash = _TrashBinState.isOverTrashLocal(
                        context,
                        centerLocal,
                      );
                      if (context.read<StickerService>().dragOverDelete !=
                          overTrash) {
                        context.read<StickerService>().setDragOverDelete(
                          overTrash,
                        );
                      }

                      svc.updateDrag(clampedDelta);
                    } catch (e) {
                      debugPrint('Long press move error: $e');
                    }
                  },
                  onLongPressEnd: (_) {
                    svc.endDrag();
                    if (mounted) setState(() => _pressing = false);
                  },
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),

          // 롱프레스 중에만 스티커 영역 전체에서 핀치 스케일 허용
          if (_pressing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (d) {
                  _pinchStartScale =
                      context.read<StickerService>().dragPreviewScale;
                },
                onScaleUpdate: (d) {
                  if (d.pointerCount < 2) return;
                  final double wanted = (_pinchStartScale * d.scale).clamp(
                    StickerService.minScale,
                    StickerService.maxScale,
                  );
                  final double delta = (wanted / _pinchStartScale).clamp(
                    0.1,
                    10.0,
                  );
                  context.read<StickerService>().updateDrag(
                    Offset.zero,
                    scaleDelta: delta,
                    rotationDelta: 0.0,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStickerBody({
    required bool selected,
    required bool isDragging,
    required bool pressing,
  }) {
    Widget body;
    switch (widget.sticker.type) {
      case StickerType.text:
        final dynamic c = widget.sticker.content;
        final String text =
            c is Map ? (c['text']?.toString() ?? '') : c.toString();
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          color: Colors.transparent,
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        break;
      case StickerType.emoji:
        body = Text(
          widget.sticker.content as String,
          style: const TextStyle(fontSize: 40),
        );
        break;
      case StickerType.drawing:
        // 벡터 기반 그리기 렌더링
        final content = widget.sticker.content as Map<String, dynamic>;
        final strokes =
            (content['strokes'] as List).cast<Map<String, dynamic>>();
        body = DrawingStickerRenderer(strokes: strokes);
        break;
      case StickerType.image:
        final content = widget.sticker.content;
        if (content is Uint8List) {
          body = SizedBox(
            width: 200, // 고정 높이로 정규화
            // 고정 높이로 정규화
            child: Image.memory(
              content,
              fit: BoxFit.contain, // 비율 유지하며 200x200 안에 맞춤
              alignment: Alignment.center,
            ),
          );
        } else if (content is String && content.startsWith('http')) {
          body = SizedBox(
            width: 200, // 고정 너비로 정규화
            child: Image.network(
              content,
              fit: BoxFit.contain, // 비율 유지하며 200x200 안에 맞춤
              alignment: Alignment.center,
            ),
          );
        } else {
          body = Container(
            width: 140,
            height: 140,
            color: Colors.grey.shade700,
          );
        }
        break;
    }

    // 히트박스 확장: 스티커 가장자리에서도 쉽게 잡히도록 투명 패딩 영역 추가
    // 단, 그리기/이미지 스티커는 패딩 없이 정확한 위치에 배치
    final double hitboxPadding =
        (widget.sticker.type == StickerType.drawing ||
                widget.sticker.type == StickerType.image)
            ? 0
            : 10;
    final Widget hitbox = Container(
      padding: EdgeInsets.all(hitboxPadding),
      color: Colors.transparent,
      child: body,
    );

    // 보더는 이동(드래그) 중 또는 길게 눌러 이동 가능 상태에서 표시
    if (!isDragging && !pressing) return hitbox;
    return Stack(
      children: [
        hitbox,
        // 터치 히트박스를 제외하고 컨텐츠 외곽선만 타이트하게 표시
        Positioned(
          left: hitboxPadding,
          right: hitboxPadding,
          top: hitboxPadding,
          bottom: hitboxPadding,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 1.5),
                borderRadius: BorderRadius.circular(0),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
