import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/sticker_service.dart';
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
        behavior: HitTestBehavior.translucent,
        // 🎯 드래그만 지원 (핀치 비활성화)
        onPanStart: (details) {
          debugPrint('[Sticker] 드래그 시작');
          try {
            context.read<EditorService>().editor.composer.clearSelection();
          } catch (e) {}
          svc.beginDrag(widget.sticker.id);
        },
        onPanUpdate: (details) {
          if (!svc.isPanning) return;

          final currentPos = svc.dragPreviewPos;
          var newPos = currentPos + details.delta;

          // 화면 경계 제한
          const minVisible = 50.0;
          newPos = Offset(
            newPos.dx.clamp(minVisible - 200, screenSize.width - minVisible),
            newPos.dy.clamp(0, double.infinity),
          );

          final adjustedDelta = newPos - currentPos;

          svc.updateDrag(
            adjustedDelta,
            scaleDelta: 1.0, // 확대 없음
            rotationDelta: 0.0, // 회전 없음
          );

          // 휴지통 영역 체크
          final centerLocal = Offset(newPos.dx + 70, newPos.dy - scrollY + 90);
          final overTrash = _TrashBinState.isOverTrashLocal(
            context,
            centerLocal,
          );
          svc.setDragOverDelete(overTrash);
        },
        onPanEnd: (details) {
          debugPrint('[Sticker] 드래그 종료');
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
    // 🎯 PNG 드로잉만 지원
    switch (sticker.type) {
      case StickerType.image:
        final content = sticker.content;
        if (content is Map) {
          // 🎯 PNG 드로잉 (URL + 크기 정보)
          final url = (content['url'] ?? '').toString();
          final width = (content['width'] as num?)?.toDouble();
          final height = (content['height'] as num?)?.toDouble();

          if (url.isNotEmpty) {
            body = SizedBox(
              width: width,
              height: height,
              child: Image.network(
                url,
                fit: BoxFit.fill, // 정확한 크기로 채우기
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: width ?? 140,
                    height: height ?? 140,
                    color: Colors.transparent,
                  );
                },
              ),
            );
          } else {
            body = Container(
              width: 140,
              height: 140,
              color: Colors.grey.shade700,
            );
          }
        } else if (content is Uint8List) {
          // 🎯 PNG 드로잉 (고화질, 업로드 전 - 레거시)
          body = Image.memory(
            content,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
          );
        } else if (content is String) {
          // 🎯 URL 이미지 (크기 정보 없음 - 레거시)
          body = Image.network(
            content,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 140,
                height: 140,
                color: Colors.transparent,
              );
            },
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

    // 🎯 드래그 중일 때 녹색 테두리 표시
    if (isDragging) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: body,
      );
    }
    return body;
  }
}
