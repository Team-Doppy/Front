import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/post_reader_stickers.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/theme/app_colors.dart';

class StickerCanvas extends StatelessWidget {
  final ScrollController scrollController;
  StickerCanvas({super.key, required this.scrollController});
  final GlobalKey _stackKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
        return Consumer<StickerService>(
          builder: (context, svc, __) {
            final ordered = [...svc.stickers]
              ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

            return Stack(
              key: _stackKey,
              children: [
                // 스티커들
                for (final s in ordered)
                  _StickerView(
                    key: ValueKey(s.id),
                    sticker: s,
                    scrollController: scrollController,
                    stackKey: _stackKey,
                  ),

                // 휴지통 (드래그 중일 때만 표시) - ValueListenableBuilder로 감지
                ValueListenableBuilder<bool>(
                  valueListenable: svc.isDraggingNotifier,
                  builder: (context, isDragging, child) {
                    if (!isDragging) return const SizedBox.shrink();
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 40, // 툴바가 있던 위치보다 조금 위
                      child: _TrashBin(stackKey: _stackKey),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
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
    final expanded = r.inflate(36);
    if (expanded.contains(localPos)) return true;
    final center = r.center;
    final double radius = (r.width / 2) + 30;
    return (localPos - center).distance <= radius;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<StickerService>();
    return Center(
      child: _Measure(
        onUpdate: (size, globalTopLeft) {
          final RenderBox? stackBox =
              widget.stackKey.currentContext?.findRenderObject() as RenderBox?;
          if (stackBox != null) {
            final Offset topLeftInStack = stackBox.globalToLocal(globalTopLeft);
            _rect = topLeftInStack & size;
          }
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: svc.dragOverDeleteNotifier,
          builder: (context, dragOverDelete, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              width: dragOverDelete ? 72 : 56,
              height: dragOverDelete ? 72 : 56,
              decoration: BoxDecoration(
                color:
                    dragOverDelete
                        ? Colors.redAccent.withOpacity(0.9)
                        : AppColors.darkSurface.withOpacity(0.6),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        dragOverDelete
                            ? Colors.redAccent.withOpacity(0.5)
                            : Colors.black.withOpacity(0.25),
                    blurRadius: dragOverDelete ? 18 : 12,
                    spreadRadius: 1,
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Icon(
                dragOverDelete ? Icons.delete_forever : Icons.delete_outline,
                color: Colors.white,
                size: dragOverDelete ? 34 : 28,
              ),
            );
          },
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
  Offset _lastGlobal = Offset.zero;
  double _lastScale = 1.0;
  double _lastRotation = 0.0;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<StickerService>();
    final scrollY =
        widget.scrollController.hasClients
            ? widget.scrollController.offset
            : 0.0;

    // 항상 ValueListenableBuilder로 위치 구독 (위젯 구조 일관성 유지)
    return ValueListenableBuilder<Offset?>(
      valueListenable: svc.dragPreviewPosNotifier,
      builder: (context, dragPos, child) {
        final isDragging = svc.isDraggingSticker(widget.sticker.id);
        final pos =
            isDragging && dragPos != null ? dragPos : widget.sticker.position;
        final scale = isDragging ? svc.dragPreviewScale : widget.sticker.scale;
        final rot =
            isDragging ? svc.dragPreviewRotation : widget.sticker.rotation;

        return _buildStickerWidget(
          context,
          pos,
          scrollY,
          scale,
          rot,
          isDragging,
        );
      },
    );
  }

  Widget _buildStickerWidget(
    BuildContext context,
    Offset pos,
    double scrollY,
    double scale,
    double rot,
    bool isDragging,
  ) {
    final svc = context.read<StickerService>();
    final screenSize = MediaQuery.of(context).size;

    // 스티커 크기에 따라 터치 영역 확장 (큰 스티커도 핀치 가능하도록)
    final touchPadding = scale > 2.0 ? 100.0 : 50.0;

    return Positioned(
      left: pos.dx - touchPadding,
      top: pos.dy - scrollY - touchPadding,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent, // 빈 영역도 터치 가능
        // onScaleStart: 1개 손가락=드래그, 2개 손가락=핀치
        onScaleStart: (details) {
          _lastGlobal = details.focalPoint;
          _lastScale = 1.0;
          _lastRotation = 0.0;
          debugPrint(
            '[Sticker] onScaleStart: pointerCount=${details.pointerCount}, scale=$scale',
          );
          try {
            context.read<EditorService>().editor.composer.clearSelection();
          } catch (e) {}
          svc.beginDrag(widget.sticker.id);
        },
        onScaleUpdate: (details) {
          if (!svc.isPanning) return;

          // 위치 이동 계산
          final delta = details.focalPoint - _lastGlobal;
          _lastGlobal = details.focalPoint;

          // 확대/축소 계산
          final scaleDelta = details.scale / _lastScale;
          _lastScale = details.scale;

          // 회전 계산
          final rotationDelta = details.rotation - _lastRotation;
          _lastRotation = details.rotation;

          debugPrint(
            '[Sticker] onScaleUpdate: scale=${details.scale.toStringAsFixed(2)}, scaleDelta=${scaleDelta.toStringAsFixed(2)}, rotation=${details.rotation.toStringAsFixed(2)}, rotDelta=${rotationDelta.toStringAsFixed(2)}, currentScale=${svc.dragPreviewScale.toStringAsFixed(2)}, pointers=${details.pointerCount}',
          );

          // 업데이트 (화면 경계 체크 포함)
          final currentPos = svc.dragPreviewPos;
          var newPos = currentPos + delta;

          // 화면 경계 제한
          // 좌측/우측: 최소 50px는 화면 안에 유지
          // 상단: 최소 0 (앱바 아래)
          // 하단: 제한 없음 (스크롤 가능)
          const minVisible = 50.0;
          newPos = Offset(
            newPos.dx.clamp(
              minVisible - 200,
              screenSize.width - minVisible,
            ), // 200은 대략 스티커 최대 너비
            newPos.dy.clamp(0, double.infinity),
          );

          // 델타 재계산 (경계 제한 후)
          final adjustedDelta = newPos - currentPos;

          // 2개 손가락일 때만 확대/축소 및 회전 적용
          final finalScaleDelta = details.pointerCount >= 2 ? scaleDelta : 1.0;
          final finalRotationDelta =
              details.pointerCount >= 2 ? rotationDelta : 0.0;

          svc.updateDrag(
            adjustedDelta,
            scaleDelta: finalScaleDelta,
            rotationDelta: finalRotationDelta,
          );

          // 휴지통 영역 체크
          final centerLocal = Offset(
            newPos.dx + 70, // 대략적인 중심
            newPos.dy - scrollY + 90,
          );
          final overTrash = _TrashBinState.isOverTrashLocal(
            context,
            centerLocal,
          );
          svc.setDragOverDelete(overTrash);
        },
        onScaleEnd: (details) {
          debugPrint(
            '[Sticker] onScaleEnd: finalScale=${svc.dragPreviewScale.toStringAsFixed(2)}, finalRotation=${svc.dragPreviewRotation.toStringAsFixed(2)}',
          );
          _lastScale = 1.0;
          _lastRotation = 0.0;
          svc.endDrag();
        },
        child: Padding(
          padding: EdgeInsets.all(touchPadding), // 터치 패딩 복원
          child: Transform(
            transform:
                Matrix4.identity()
                  ..rotateZ(rot)
                  ..scale(scale),
            alignment: Alignment.center,
            transformHitTests: true, // 변환된 크기로 히트 테스트
            child: Opacity(
              opacity: widget.sticker.opacity,
              child: _buildBody(widget.sticker, isDragging),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Sticker sticker, bool isDragging) {
    Widget body;
    switch (sticker.type) {
      case StickerType.text:
        final c = sticker.content;
        final text = c is Map ? (c['text']?.toString() ?? '') : c.toString();
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
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
        body = Container(
          padding: const EdgeInsets.all(8),
          child: Text(
            sticker.content as String,
            style: const TextStyle(fontSize: 40),
          ),
        );
        break;
      case StickerType.drawing:
        final content = sticker.content as Map<String, dynamic>;
        final strokes =
            (content['strokes'] as List).cast<Map<String, dynamic>>();
        body = DrawingStickerRenderer(strokes: strokes);
        break;
      case StickerType.image:
        final content = sticker.content;
        if (content is Uint8List) {
          body = SizedBox(
            width: 200,
            child: Image.memory(content, fit: BoxFit.contain),
          );
        } else if (content is String && content.startsWith('http')) {
          body = SizedBox(
            width: 200,
            child: Image.network(content, fit: BoxFit.contain),
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

    // 드래그 중일 때만 녹색 테두리 표시
    if (isDragging) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.greenAccent, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: body,
      );
    }
    return body;
  }
}
