import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/overlay/sticker_overlay.dart';

class StickerCanvas extends StatelessWidget {
  final ScrollController scrollController;
  const StickerCanvas({super.key, required this.scrollController});
  static final GlobalKey _stackKey = GlobalKey();

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
                    ),

                  // 드래그 프리뷰 오버레이 비활성화 (삭제 판정은 onScaleUpdate에서 직접 수행)

                  // 하단 중앙 휴지통: 어떤 스티커든 드래그 중이면 노출
                  if (context.select<StickerService, bool>(
                    (svc) => svc.isDragging,
                  ))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 20, // 툴바에 가리지 않으면서 조금 더 아래 배치
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
    final double radius = (r.width / 2) + 36;
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
          duration: const Duration(milliseconds: 140),
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
  const _StickerView({
    super.key,
    required this.sticker,
    required this.scrollController,
  });

  @override
  State<_StickerView> createState() => _StickerViewState();
}

class _StickerViewState extends State<_StickerView>
    with SingleTickerProviderStateMixin {
  Offset _lastFocalPoint = Offset.zero;
  bool _pressing = false;
  Size _stickerSize = const Size(140, 140);
  late final AnimationController _appearCtrl;

  @override
  void initState() {
    super.initState();
    _appearCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() {}));
    _appearCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant _StickerView oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _appearCtrl.dispose();
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
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // 선택 처리
          svc.select(widget.sticker.id);
          // 즉시 오버레이 열어 편집(모드 선택 생략).
          Navigator.of(context).push(
            PageRouteBuilder(
              opaque: false,
              barrierDismissible: true,
              pageBuilder:
                  (_, __, ___) => StickerOverlay(
                    initialKind:
                        widget.sticker.type == StickerType.text
                            ? StickerKind.text
                            : widget.sticker.type == StickerType.emoji
                            ? StickerKind.emoji
                            : StickerKind.image,
                    initialText:
                        widget.sticker.type == StickerType.text
                            ? (widget.sticker.content is Map
                                ? (((widget.sticker.content as Map)['text'])
                                        ?.toString() ??
                                    '')
                                : (widget.sticker.content as String))
                            : null,
                    initialEmoji:
                        widget.sticker.type == StickerType.emoji
                            ? (widget.sticker.content as String)
                            : null,
                    initialImage:
                        widget.sticker.type == StickerType.image
                            ? (widget.sticker.content is Uint8List
                                ? widget.sticker.content as Uint8List
                                : null)
                            : null,
                    onSubmit: ({
                      required String text,
                      String? emoji,
                      Uint8List? image,
                      Map<String, dynamic>? textStyle,
                    }) {
                      // 기존 스티커 내용 업데이트 (타입 유지, content만 교체)
                      final id = widget.sticker.id;
                      if (image != null) {
                        svc.updateContent(id, image);
                      } else if ((emoji ?? '').isNotEmpty) {
                        svc.updateContent(id, emoji);
                      } else {
                        // 텍스트는 style 동반 저장 형식 유지
                        final content = <String, dynamic>{
                          'text': text.trim(),
                          'style': textStyle,
                        };
                        svc.updateContent(id, content);
                      }
                    },
                  ),
            ),
          );
        },
        onScaleStart: (d) {
          _lastFocalPoint = d.focalPoint;
          setState(() => _pressing = true);
          // 스티커 조작 시 키보드 자동 내리기 (커서 비활성화)
          FocusScope.of(context).unfocus();
          svc.beginDrag(widget.sticker.id);
          svc.bringToFront(widget.sticker.id);
        },
        onScaleUpdate: (d) {
          // 드래그와 스케일/회전을 모두 처리
          final delta = d.focalPoint - _lastFocalPoint;
          _lastFocalPoint = d.focalPoint;
          // 스케일 클램프 적용: 너무 커지거나 작아지지 않도록 제한
          final double nextScale = (d.scale).clamp(
            StickerService.minScale,
            StickerService.maxScale,
          );
          // 수직 이동 범위 제한: 현재 뷰포트 내에서만 이동
          final double scrollY =
              widget.scrollController.hasClients
                  ? widget.scrollController.offset
                  : 0.0;
          final Size vs = MediaQuery.of(context).size;
          final Offset cur = context.read<StickerService>().dragPreviewPos;
          final Offset want = cur + delta;
          // 여백을 조금 두어 하단 툴바/휴지통 등을 고려
          const double topMargin = 0.0;
          const double bottomMargin = 120.0;
          const double extraBottomAllowance = 200.0; // 더 아래로 허용
          const double leftMargin = 12.0;
          const double rightMargin = 12.0;
          final double effW = (_stickerSize.width) * nextScale;
          final double effH = (_stickerSize.height) * nextScale;
          final double minY = scrollY + topMargin;
          final double safeBottom = MediaQuery.of(context).padding.bottom;
          double maxY =
              scrollY +
              vs.height -
              bottomMargin -
              safeBottom -
              effH +
              extraBottomAllowance;
          final double clampedY = want.dy.clamp(minY, maxY);
          final double minX = leftMargin;
          final double maxX = vs.width - rightMargin - effW;
          final double clampedX = want.dx.clamp(minX, maxX);
          final Offset clampedDelta = Offset(
            clampedX - cur.dx,
            clampedY - cur.dy,
          );

          // 휴지통 hover 판정을 오버레이 없이 직접 계산
          final Offset newTopLeft = Offset(clampedX, clampedY);
          final Offset centerLocal = Offset(
            newTopLeft.dx + (effW / 2),
            newTopLeft.dy - scrollY + (effH / 2),
          );
          final bool overTrash = _TrashBinState.isOverTrashLocal(
            context,
            centerLocal,
          );
          if (context.read<StickerService>().dragOverDelete != overTrash) {
            context.read<StickerService>().setDragOverDelete(overTrash);
          }

          svc.updateDrag(
            clampedDelta,
            scaleDelta: nextScale,
            rotationDelta: d.rotation,
          );
        },
        onScaleEnd: (_) {
          // 최종 적용
          svc.endDrag();
          if (mounted) setState(() => _pressing = false);
        },
        child: RepaintBoundary(
          child: Transform(
            transform:
                Matrix4.identity()
                  ..rotateZ(rot)
                  ..scale(
                    scale *
                        (_appearCtrl.isAnimating || _appearCtrl.isCompleted
                            ? (0.82 +
                                0.18 *
                                    Curves.easeOutBack.transform(
                                      _appearCtrl.value,
                                    ))
                            : 1.0),
                  ),
            alignment: Alignment.center,
            child: Opacity(
              opacity:
                  widget.sticker.opacity *
                  (_appearCtrl.isAnimating || _appearCtrl.isCompleted
                      ? Curves.easeOut.transform(_appearCtrl.value)
                      : 1.0),
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
      case StickerType.image:
        final content = widget.sticker.content;
        if (content is Uint8List) {
          body = ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
              child: Image.memory(
                content,
                fit: BoxFit.contain, // 원본 비율 유지
              ),
            ),
          );
        } else if (content is String && content.startsWith('http')) {
          body = ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
              child: Image.network(
                content,
                fit: BoxFit.contain, // 원본 비율 유지
              ),
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
    final Widget hitbox = Container(
      padding: const EdgeInsets.all(10),
      color: Colors.transparent,
      child: body,
    );

    // 보더는 이동(드래그) 중 또는 길게 눌러 이동 가능 상태에서 표시
    if (!isDragging && !pressing) return hitbox;
    return Stack(
      children: [
        hitbox,
        // 터치 히트박스(padding:10)를 제외하고 컨텐츠 외곽선만 타이트하게 표시
        Positioned(
          left: 10,
          right: 10,
          top: 10,
          bottom: 10,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
