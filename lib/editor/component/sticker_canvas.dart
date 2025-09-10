import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/theme/app_colors.dart';

class StickerCanvas extends StatelessWidget {
  final ScrollController scrollController;
  const StickerCanvas({super.key, required this.scrollController});

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
                children: [
                  for (final s in ordered)
                    _StickerView(
                      key: ValueKey<String>(s.id),
                      sticker: s,
                      scrollController: scrollController,
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

class _StickerViewState extends State<_StickerView> {
  Offset _basePos = Offset.zero;
  double _baseScale = 1.0;
  double _baseRot = 0.0;
  Offset _lastFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _basePos = widget.sticker.position;
    _baseScale = widget.sticker.scale;
    _baseRot = widget.sticker.rotation;
  }

  @override
  void didUpdateWidget(covariant _StickerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sticker != widget.sticker) {
      _basePos = widget.sticker.position;
      _baseScale = widget.sticker.scale;
      _baseRot = widget.sticker.rotation;
    }
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
    return Positioned(
      left: widget.sticker.position.dx,
      top: widget.sticker.position.dy - scrollY,
      child: GestureDetector(
        onTap: () => svc.select(widget.sticker.id),
        onScaleStart: (d) {
          _lastFocalPoint = d.focalPoint;
          _basePos = widget.sticker.position;
          _baseScale = widget.sticker.scale;
          _baseRot = widget.sticker.rotation;
          svc.bringToFront(widget.sticker.id);
        },
        onScaleUpdate: (d) {
          // 드래그와 스케일/회전을 모두 처리
          final delta = d.focalPoint - _lastFocalPoint;
          _lastFocalPoint = d.focalPoint;

          // 드래그 민감도 조절 (1.0으로 복원)
          final newPosition = _basePos + delta;
          final newScale = (_baseScale * d.scale).clamp(0.3, 4.0);
          final newRotation = _baseRot + d.rotation;

          // 화면 경계 내로 제한
          final screenSize = MediaQuery.of(context).size;
          final scrollY =
              widget.scrollController.hasClients
                  ? widget.scrollController.offset
                  : 0.0;

          final stickerSize = 140.0 * newScale;
          final clampedX = newPosition.dx.clamp(
            0.0,
            screenSize.width - stickerSize,
          );
          final clampedY = newPosition.dy.clamp(
            scrollY,
            scrollY + screenSize.height - stickerSize,
          );

          svc.transform(
            widget.sticker.id,
            position: Offset(clampedX, clampedY),
            scale: newScale,
            rotation: newRotation,
          );
        },
        child: Transform(
          transform:
              Matrix4.identity()
                ..rotateZ(widget.sticker.rotation)
                ..scale(widget.sticker.scale),
          alignment: Alignment.center,
          child: Opacity(
            opacity: widget.sticker.opacity,
            child: _buildStickerBody(selected),
          ),
        ),
      ),
    );
  }

  Widget _buildStickerBody(bool selected) {
    Widget body;
    switch (widget.sticker.type) {
      case StickerType.text:
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.darkSurface.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.sticker.content as String,
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
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              content,
              width: 140,
              height: 140,
              fit: BoxFit.cover,
            ),
          );
        } else if (content is String && content.startsWith('http')) {
          body = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              content,
              width: 140,
              height: 140,
              fit: BoxFit.cover,
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

    if (!selected) return body;
    return Stack(
      children: [
        body,
        Positioned.fill(
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
