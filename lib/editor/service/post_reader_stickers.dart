import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:flutter/rendering.dart';

/// 스티커 오버레이 (리더/에디터 공용)
class PostReaderStickers extends StatelessWidget {
  const PostReaderStickers({
    super.key,
    required this.stickers,
    required this.layoutKey,
    required this.stackKey,
    required this.scrollController,
  });

  final List stickers;
  final GlobalKey layoutKey;
  final GlobalKey stackKey;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[];
        final double scrollY =
            scrollController.hasClients ? scrollController.offset : 0.0;

        // zIndex 기준으로 정렬하여 안정적인 레이어링 보장
        final sorted = List.from(stickers);
        sorted.sort((a, b) {
          final ma = (a as Map).cast<String, dynamic>();
          final mb = (b as Map).cast<String, dynamic>();
          final za = (ma['zIndex'] as num?)?.toInt() ?? 0;
          final zb = (mb['zIndex'] as num?)?.toInt() ?? 0;
          return za.compareTo(zb);
        });

        for (final s in sorted) {
          final m = (s as Map).cast<String, dynamic>();
          final type = (m['type'] ?? '').toString();
          // zIndex는 정렬에만 사용되었으며 여기선 미사용
          final rot = (m['rotation'] as num?)?.toDouble() ?? 0.0;
          final scale = (m['scale'] as num?)?.toDouble() ?? 1.0;
          final anchor = (m['anchor'] as Map?)?.cast<String, dynamic>();
          late final Offset absPos;
          late final bool needsScrollCompensation;

          if (anchor != null) {
            absPos = _resolveAnchor(anchor);
            needsScrollCompensation = false;
          } else {
            final pf =
                (m['positionFallback'] as Map?)?.cast<String, dynamic>() ?? {};
            // 문서 기준 폭이 제공되면 현재 폭 대비 보정
            final docWidth = (pf['docWidth'] as num?)?.toDouble();
            final currentWidth = constraints.maxWidth;
            final scale =
                (docWidth != null && docWidth > 0)
                    ? (currentWidth / docWidth)
                    : 1.0;
            absPos = Offset(
              ((pf['xPx'] as num?)?.toDouble() ?? 0.0) * scale,
              ((pf['yPx'] as num?)?.toDouble() ?? 0.0) * scale,
            );
            needsScrollCompensation = true;
          }

          Widget body;
          if (type == 'text') {
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final text = (content['text'] ?? '').toString();
            final style =
                (content['style'] as Map?)?.cast<String, dynamic>() ?? {};
            body = RepaintBoundary(
              child: Text(
                text,
                style: TextStyle(
                  color: _toColor(style['color']) ?? Colors.white,
                  fontSize: (style['fontSize'] as num?)?.toDouble() ?? 32,
                  fontWeight:
                      (style['bold'] == true)
                          ? FontWeight.w800
                          : FontWeight.w500,
                  fontStyle:
                      (style['italic'] == true)
                          ? FontStyle.italic
                          : FontStyle.normal,
                  decoration:
                      (style['underline'] == true)
                          ? TextDecoration.underline
                          : TextDecoration.none,
                  letterSpacing:
                      (style['letterSpacing'] as num?)?.toDouble() ?? 0,
                ),
              ),
            );
          } else if (type == 'emoji') {
            final content = (m['content'] ?? '').toString();
            body = const RepaintBoundary(
              child: Text('🙂', style: TextStyle(fontSize: 40)),
            );
            // 실제 이모지 표시
            body = RepaintBoundary(
              child: Text(content, style: const TextStyle(fontSize: 40)),
            );
          } else if (type == 'image') {
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final dynamic raw = content['bytes'];
            if (raw != null) {
              try {
                final bytes =
                    raw is String ? base64Decode(raw) : raw as Uint8List;
                body = RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 200,
                        maxHeight: 200,
                      ),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                );
              } catch (_) {
                body = Container(
                  width: 140,
                  height: 140,
                  color: Colors.grey[700],
                );
              }
            } else if ((content['url'] ?? '').toString().isNotEmpty) {
              final url = (content['url'] ?? '').toString();
              body = RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 200,
                    ),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      cacheWidth: 300,
                      cacheHeight: 300,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              );
            } else {
              body = Container(
                width: 140,
                height: 140,
                color: Colors.grey[700],
              );
            }
          } else if (type == 'drawing') {
            // drawing 타입 스티커 렌더링
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final strokes = (content['strokes'] as List?) ?? [];
            body = RepaintBoundary(
              child: DrawingStickerRenderer(
                strokes: strokes.cast<Map<String, dynamic>>(),
              ),
            );
          } else {
            body = const SizedBox.shrink();
          }

          final double topPos =
              needsScrollCompensation ? (absPos.dy - scrollY) : absPos.dy;

          children.add(
            Positioned(
              left: absPos.dx,
              top: topPos,
              child: Transform(
                alignment: Alignment.center,
                transform:
                    Matrix4.identity()
                      ..rotateZ(rot)
                      ..scale(scale),
                child: body,
              ),
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  Offset _resolveAnchor(Map<String, dynamic> anchor) {
    final nodeId = (anchor['nodeId'] ?? '').toString();
    final relX = (anchor['relX'] as num?)?.toDouble() ?? 0.5;
    final relY = (anchor['relY'] as num?)?.toDouble() ?? 0.0;

    final layout = layoutKey.currentState as DocumentLayout?;
    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (layout == null || stackBox == null) return const Offset(0, 0);
    try {
      final rect = layout.getRectForSelection(
        DocumentPosition(
          nodeId: nodeId,
          nodePosition: const UpstreamDownstreamNodePosition.upstream(),
        ),
        DocumentPosition(
          nodeId: nodeId,
          nodePosition: const UpstreamDownstreamNodePosition.downstream(),
        ),
      );
      if (rect == null) return const Offset(0, 0);
      final topLeftInStack = stackBox.globalToLocal(rect.topLeft);
      final x = topLeftInStack.dx + relX * rect.width;
      final y = topLeftInStack.dy + relY * rect.height;
      return Offset(x, y);
    } catch (_) {
      return const Offset(0, 0);
    }
  }

  Color? _toColor(dynamic v) {
    if (v is String && v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }
}

/// 벡터 기반 그리기 렌더러
/// 에디터와 PostReaderScreen에서 공유
class DrawingStickerRenderer extends StatelessWidget {
  final List<Map<String, dynamic>> strokes;

  const DrawingStickerRenderer({super.key, required this.strokes});

  @override
  Widget build(BuildContext context) {
    // 스트로크 경계 계산
    final bounds = _computeBounds();
    if (bounds == null) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _VectorDrawingPainter(strokes: strokes),
        size: Size(bounds.width, bounds.height),
        isComplex: true,
        willChange: false,
      ),
    );
  }

  Rect? _computeBounds() {
    if (strokes.isEmpty) return null;
    double? minX, minY, maxX, maxY;

    for (final strokeData in strokes) {
      final points =
          (strokeData['points'] as List).cast<Map<String, dynamic>>();
      final width = (strokeData['width'] as num?)?.toDouble() ?? 8.0;
      final half = width / 2;

      for (final p in points) {
        final x = (p['x'] as num).toDouble();
        final y = (p['y'] as num).toDouble();

        final x1 = x - half;
        final y1 = y - half;
        final x2 = x + half;
        final y2 = y + half;

        minX = (minX == null) ? x1 : (x1 < minX ? x1 : minX);
        minY = (minY == null) ? y1 : (y1 < minY ? y1 : minY);
        maxX = (maxX == null) ? x2 : (x2 > maxX ? x2 : maxX);
        maxY = (maxY == null) ? y2 : (y2 > maxY ? y2 : maxY);
      }
    }

    if (minX == null || minY == null || maxX == null || maxY == null) {
      return null;
    }

    // 패딩 최소화 (선 두께가 이미 반영되어 있음)
    const double pad = 0.5;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }
}

/// 벡터 그리기 페인터
class _VectorDrawingPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;

  _VectorDrawingPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final strokeData in strokes) {
      final points =
          (strokeData['points'] as List).cast<Map<String, dynamic>>();
      if (points.isEmpty) continue;

      final colorHex = strokeData['color'] as String? ?? '#FFFFFFFF';
      final width = (strokeData['width'] as num?)?.toDouble() ?? 8.0;
      final erase = strokeData['erase'] as bool? ?? false;

      // Hex 색상 파싱
      final colorValue = int.parse(colorHex.replaceAll('#', ''), radix: 16);
      final color = Color(colorValue);

      final paint =
          Paint()
            ..color = erase ? Colors.transparent : color
            ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver
            ..strokeWidth = width
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;

      final path = Path();
      final firstPoint = points.first;
      path.moveTo(
        (firstPoint['x'] as num).toDouble(),
        (firstPoint['y'] as num).toDouble(),
      );

      for (int i = 1; i < points.length; i++) {
        final p = points[i];
        path.lineTo((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorDrawingPainter oldDelegate) {
    // 스트로크 리스트의 참조가 바뀌었을 때만 다시 그림
    return strokes != oldDelegate.strokes;
  }
}
