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
              Size? bodySize;

              // 🎯 PNG 드로잉만 지원 (type == 'image'만 처리)
              if (type == 'image') {
                final content =
                    (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
                final dynamic raw = content['bytes'];
                if (raw != null) {
                  try {
                    final bytes =
                        raw is String ? base64Decode(raw) : raw as Uint8List;

                    // 🎯 PNG 드로잉 (고화질 원본)
                    body = RepaintBoundary(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
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
                  final width = (content['width'] as num?)?.toDouble();
                  final height = (content['height'] as num?)?.toDouble();

                  // 🎯 PNG 드로잉 (URL + 크기 정보)
                  if (width != null && height != null) {
                    bodySize = Size(width, height); // 크기 정보 사용
                    body = RepaintBoundary(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Image.network(
                          url,
                          fit: BoxFit.fill, // 정확한 크기
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                        ),
                      ),
                    );
                  } else {
                    // 레거시: 크기 정보 없음
                    body = RepaintBoundary(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                      ),
                    );
                  }
                } else {
                  body = Container(
                    width: 140,
                    height: 140,
                    color: Colors.grey[700],
                  );
                }
              } else {
                // 🎯 text, emoji, drawing 타입은 무시
                continue;
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
}

// 🎯 벡터 드로잉 제거됨 (PNG만 지원)
