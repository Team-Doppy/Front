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
    this.topInset = 0,
  });

  final List stickers;
  final GlobalKey layoutKey;
  final GlobalKey stackKey;
  final ScrollController scrollController;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
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
              double baseScale = (m['scale'] as num?)?.toDouble() ?? 1.0;
              final anchor = (m['anchor'] as Map?)?.cast<String, dynamic>();
              late final Offset absPos;
              late final bool needsScrollCompensation;
              double anchorScale = 1.0; // 앵커 기준 스케일 보정 (refW 대비 현재 width)

              Rect? nodeRectForAnchor;

              bool anchorHasRefW = false;
              bool anchorHasLocal = false;
              if (anchor != null) {
                final resolved = _resolveAnchor(anchor);
                if (resolved != null) {
                  absPos = resolved;
                } else {
                  // 앵커 좌표를 얻지 못하면 안전 폴백
                  final pf =
                      (m['positionFallback'] as Map?)
                          ?.cast<String, dynamic>() ??
                      {};
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
                  // refW 기반 보정은 불가
                }
                // refW/refH가 있으면 현재 노드 크기 대비 스케일 보정
                final nodeId = (anchor['nodeId'] ?? '').toString();
                nodeRectForAnchor = _getNodeRect(nodeId);
                final refW = (anchor['refW'] as num?)?.toDouble();
                if (nodeRectForAnchor != null && refW != null && refW > 0) {
                  anchorScale = nodeRectForAnchor.width / refW;
                  anchorHasRefW = true;
                }
                // localX/localY를 사용한 앵커인지 체크 → 이 경우에는 중심 보정 금지
                if (anchor.containsKey('localX') ||
                    anchor.containsKey('localY')) {
                  anchorHasLocal = true;
                }
                if (resolved != null) {
                  needsScrollCompensation = false;
                }
              } else {
                final pf =
                    (m['positionFallback'] as Map?)?.cast<String, dynamic>() ??
                    {};
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
              Size? bodySize; // 드로잉 등 크기 중심 보정용
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
                // 드로잉 바운딩 박스 계산하여 중심 보정에 사용
                final bounds = _computeDrawingBounds(strokes);
                if (bounds != null) {
                  bodySize = Size(bounds.width, bounds.height);
                }
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

              // 최종 스케일: 저장된 스케일 * 앵커 스케일 보정
              final double finalScale = baseScale * anchorScale;

              // 드로잉 등은 앵커 지점이 중앙이 되도록 보정 (local 앵커가 아닐 때만)
              double left = absPos.dx;
              double top = topPos + topInset;
              // 구버전(anchor에 refW가 없는) 데이터는 좌상단 기준으로 저장됨 → 중심 보정 금지
              if (bodySize != null && anchorHasRefW && !anchorHasLocal) {
                left = absPos.dx - (bodySize.width * finalScale) / 2;
                top = topPos - (bodySize.height * finalScale) / 2 + topInset;
              }

              children.add(
                Positioned(
                  left: left,
                  top: top,
                  child: Transform(
                    alignment: Alignment.center,
                    transform:
                        Matrix4.identity()
                          ..rotateZ(rot)
                          ..scale(finalScale),
                    child: body,
                  ),
                ),
              );
            }
            return Stack(children: children);
          },
        );
      },
    );
  }

  Rect? _getNodeRect(String nodeId) {
    final layout = layoutKey.currentState as DocumentLayout?;
    if (layout == null) return null;
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
      return rect;
    } catch (_) {
      return null;
    }
  }

  // 드로잉 바운딩 박스 계산 (렌더러와 동일 로직)
  Rect? _computeDrawingBounds(List strokes) {
    if (strokes.isEmpty) return null;
    double? minX, minY, maxX, maxY;
    for (final strokeData in strokes) {
      final points =
          (strokeData['points'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
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
    if (minX == null || minY == null || maxX == null || maxY == null)
      return null;
    const double pad = 0.5;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  Offset? _resolveAnchor(Map<String, dynamic> anchor) {
    final nodeId = (anchor['nodeId'] ?? '').toString();
    final hasLocal =
        anchor.containsKey('localX') || anchor.containsKey('localY');
    final double? localX = (anchor['localX'] as num?)?.toDouble();
    final double? localY = (anchor['localY'] as num?)?.toDouble();
    final double relX = (anchor['relX'] as num?)?.toDouble() ?? 0.5;
    final double relY = (anchor['relY'] as num?)?.toDouble() ?? 0.0;

    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return null;
    try {
      final rect = _getNodeRect(nodeId);
      if (rect == null) return null;
      // _getNodeRect는 전역 좌표. Stack 로컬로 변환
      final topLeftInStack = stackBox.globalToLocal(rect.topLeft);
      // 로컬(px)+스케일(refW) 기반을 우선 사용
      if (hasLocal && localX != null && localY != null) {
        final double refW = (anchor['refW'] as num?)?.toDouble() ?? rect.width;
        final double scale = refW > 0 ? (rect.width / refW) : 1.0;
        final double x = topLeftInStack.dx + (localX * scale);
        final double y = topLeftInStack.dy + (localY * scale);
        return Offset(x, y);
      }
      // 호환: 비율(relX/relY) 기반 해석
      final double xr = topLeftInStack.dx + relX * rect.width;
      final double yr = topLeftInStack.dy + relY * rect.height;
      return Offset(xr, yr);
    } catch (_) {
      return null;
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

    // 저장된 좌표는 이미 (0,0) 기준 상대 좌표이므로,
    // bounds의 left, top이 0이 아닐 수 있지만 (패딩이나 음수 선 두께 반영)
    // 실제 그리기는 bounds.left, bounds.top을 고려해서 offset 조정 필요
    final offset = Offset(bounds.left, bounds.top);

    return RepaintBoundary(
      child: CustomPaint(
        painter: _VectorDrawingPainter(strokes: strokes, offset: offset),
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
        // 저장된 좌표는 이미 bounds 기준 상대 좌표이므로 그대로 사용
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
    // minX, minY가 0 근처일 수 있지만, 음수일 수도 있으므로 그대로 사용
    const double pad = 0.5;
    // bounds는 상대 좌표 기준이므로, (0,0)을 기준으로 하는 Rect 생성
    // 하지만 실제로는 최소값이 음수일 수 있으므로 그대로 사용
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }
}

/// 벡터 그리기 페인터
class _VectorDrawingPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final Offset offset; // bounds의 최소값 (minX, minY)

  _VectorDrawingPainter({required this.strokes, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    // bounds의 offset만큼 이동 (bounds의 좌상단이 (0,0)이 되도록)
    canvas.translate(-offset.dx, -offset.dy);

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
      // 저장된 좌표는 이미 상대 좌표이므로 그대로 사용
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
