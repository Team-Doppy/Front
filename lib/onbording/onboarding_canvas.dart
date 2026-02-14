import 'dart:math' as math;
import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:flutter/material.dart';

// =============================================================================
// 온보딩 전용 하드코딩 — 노드 크기·간격·색상 미세조정
// =============================================================================

/// 노드: 메인(북두/강조) 반지름 (씬 단위)
const double kOnboardingNodeRadius = 24.0;

/// 기본 모드: 노드 반지름 통일
const double kOnboardingDefaultNodeRadius = 16.0;

/// 노드: intensity 1(뮤트)일 때 메인 대비 배율 (0.5 ~ 1.0)
const double kOnboardingNodeRadiusMutedScale = 0.52;

/// 연결선: 기본 두께 (씬 단위, zoom 곱해짐)
const double kOnboardingLineStrokeWidth = 1.6;

/// 연결선: 기본 불투명도 (0.0 ~ 1.0)
const double kOnboardingLineOpacity = 0.52;

/// 색: intensity 3 (북두칠성 등) — 기본 모드에서만 보이는 메인
const Color kOnboardingColorIntensity3 = Colors.white;

/// 색: intensity 1 (나머지) — 뮤트
const Color kOnboardingColorIntensity1 = Color(0x0FFFFFFF); // white 6%

/// 색: 검색결과로 강조될 때 primary 대신 쓸 색 (필요 시 조정)
// final Color kOnboardingColorPrimary = ...

/// 색: 연결선
const Color kOnboardingLineColor = Color(0x80FFFFFF); // white 50%

/// 검색결과 모드: 비결과 노드 불투명도 (0.0 ~ 1.0)
const double kOnboardingNonResultOpacity = 0.35;

/// 검색결과 모드: 결과 노드 확대 배율 (메인 canvas와 동일)
const double kOnboardingSearchResultNodeScale = 1.3;

/// 기본 모드: base(50%) ↔ primary 구간만 lerp. primary는 Theme.of → 다크에서 흰색
const Color kOnboardingLerpBase = Color(0xFF6B7280);
const double kOnboardingDefaultModeLerpMinT = 0.5;
const double kOnboardingDefaultModeLerpMaxT = 1.0;

double _hash01(int n) {
  final x = math.sin(n * 12.9898) * 43758.5453;
  final f = x - x.floorToDouble();
  return f < 0 ? -f : f;
}

Color _defaultModeColorForNode(int nodeId, Color themePrimary) {
  final t01 = _hash01(nodeId);
  final t =
      kOnboardingDefaultModeLerpMinT +
      (kOnboardingDefaultModeLerpMaxT - kOnboardingDefaultModeLerpMinT) * t01;
  return Color.lerp(kOnboardingLerpBase, themePrimary, t) ?? themePrimary;
}

// =============================================================================

/// 온보딩 전용 그래프 페인터. 위 상수만 바꿔서 노드 크기·간격·색상 미세조정.
class OnboardingGraphPainter extends CustomPainter {
  OnboardingGraphPainter({
    required this.graph,
    required this.revision,
    required this.primaryColor,
    this.overridePositions,
    this.viewport,
    this.resultNodeIds,
    this.searchResultExitT,
    this.searchResultIntroAnimation,
    this.searchWaveAnimation,
    this.searchWaveFadeOutT,
    this.searchWaveIntroT,
    this.zoom = 1.0,
  });

  final GraphData graph;
  final int revision;
  final Color primaryColor;
  final Map<int, Offset>? overridePositions;
  final Rect? viewport;
  final Set<int>? resultNodeIds;
  final double? searchResultExitT;
  final Animation<double>? searchResultIntroAnimation;

  /// 검색 중 파도 효과 (0~1 반복). 기본 캔버스와 동일한 위아래 움직임.
  final Animation<double>? searchWaveAnimation;

  /// 검색결과 진입 시 파도 진폭을 0으로 줄이는 페이드아웃 (0=풀파도, 1=끔)
  final double? searchWaveFadeOutT;

  /// 파도 시작 시 진폭 인트로 (0=없음, 1=풀파도) — 검색결과→기본 전환 후 튐 방지
  final double? searchWaveIntroT;
  final double zoom;

  final Paint _linePaint = Paint()..style = PaintingStyle.stroke;
  final Paint _nodePaint = Paint()..style = PaintingStyle.fill;

  Offset _posForNode(GraphNode node) =>
      overridePositions?[node.id] ?? node.position;

  Offset _waveOffsetForNode({
    required GraphNode node,
    required Offset basePos,
  }) {
    final a = searchWaveAnimation;
    if (a == null) return Offset.zero;
    final fade = (searchWaveFadeOutT ?? 0.0).clamp(0.0, 1.0);
    if (fade >= 1.0) return Offset.zero;
    final intro = (searchWaveIntroT ?? 1.0).clamp(0.0, 1.0);
    if (intro <= 0.0) return Offset.zero;
    final phase = a.value;
    final lag =
        ((node.id * 0.073) + (basePos.dy * 0.0013) + (basePos.dx * 0.0009));
    final tt = phase - lag;
    final t = tt - tt.floorToDouble();
    final wave = math.sin(t * math.pi);
    final amp =
        (kOnboardingDefaultNodeRadius * 2.8).clamp(18.0, 38.0) *
        (1.0 - fade) *
        intro;
    return Offset(0, -amp * wave);
  }

  Offset _resultIntroOffsetForNode({
    required GraphNode node,
    required Offset basePos,
    required Offset resultsCenter,
  }) {
    final a = searchResultIntroAnimation;
    if (a == null) return Offset.zero;
    final tRaw = a.value.clamp(0.0, 1.0);
    final t = Curves.easeOutCubic.transform(tRaw);
    final rise = 38.0 * (1.0 - t);
    final d = basePos - resultsCenter;
    final dist = d.distance;
    final dir = dist <= 1e-3 ? const Offset(0, -1) : d / dist;
    final out = 22.0 * t + 14.0 * math.sin(t * math.pi);
    return Offset(dir.dx * out, dir.dy * out + rise);
  }

  static Offset _spreadFromPos(
    Offset fromCenter,
    Offset toCenter,
    int edgeIndex,
    int edgeCount,
    double nodeRadius,
  ) {
    final d = toCenter - fromCenter;
    final dist = d.distance;
    if (dist < 1e-6) return fromCenter;
    final dir = d / dist;
    const spreadDeg = 2.8;
    final angleRad =
        (edgeIndex - (edgeCount - 1) / 2) * spreadDeg * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final rotated = Offset(
      dir.dx * cosA - dir.dy * sinA,
      dir.dx * sinA + dir.dy * cosA,
    );
    return fromCenter + rotated * nodeRadius;
  }

  static Offset _spreadToPos(
    Offset fromCenter,
    Offset toCenter,
    Offset newFromPos,
    double nodeRadius,
  ) {
    final d = toCenter - newFromPos;
    final dist = d.distance;
    if (dist < 1e-6) return toCenter;
    final dir = d / dist;
    return toCenter - dir * nodeRadius;
  }

  /// 온보딩: 엣지 수가 적으므로 전부 그림 (별자리 선이 끊기지 않도록)
  Iterable<GraphEdge> _pickEdgesToDraw() => graph.edges;

  List<GraphNode> _visibleNodes() {
    final nodes = graph.nodes;
    if (viewport == null) return nodes;
    final r = viewport!;
    final pad = Rect.fromLTRB(
      r.left - 80,
      r.top - 80,
      r.right + 80,
      r.bottom + 80,
    );
    return nodes.where((n) => pad.contains(_posForNode(n))).toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final inSearchResultMode =
        resultNodeIds != null && resultNodeIds!.isNotEmpty;
    final exitT =
        (searchResultExitT != null) ? searchResultExitT!.clamp(0.0, 1.0) : 0.0;

    Offset resultsCenter = Offset.zero;
    if (inSearchResultMode && searchResultIntroAnimation != null) {
      double sx = 0, sy = 0;
      int c = 0;
      for (final n in graph.nodes) {
        if (!resultNodeIds!.contains(n.id)) continue;
        final p = _posForNode(n);
        sx += p.dx;
        sy += p.dy;
        c++;
      }
      if (c > 0) resultsCenter = Offset(sx / c, sy / c);
    }

    final introBlend = (searchResultExitT != null) ? 1.0 - exitT : 1.0;
    final edgesToDraw = _pickEdgesToDraw().toList();
    final perFromCount = <int, int>{};
    for (final e in edgesToDraw) {
      perFromCount[e.fromNodeId] = (perFromCount[e.fromNodeId] ?? 0) + 1;
    }
    final perFromIndex = <int, int>{};

    // 1. 엣지 — 검색결과 모드일 때만 표시
    if (inSearchResultMode) {
      final zoomFactor = zoom.clamp(0.4, 5.0);
      final lineW = (kOnboardingLineStrokeWidth * zoomFactor).clamp(0.4, 2.2);
      _linePaint
        ..color = kOnboardingLineColor.withOpacity(
          kOnboardingLineOpacity.clamp(0.08, 1.0),
        )
        ..strokeWidth = lineW
        ..strokeCap = StrokeCap.round;

      for (final edge in edgesToDraw) {
        final isResultEdge =
            resultNodeIds!.contains(edge.fromNodeId) &&
            resultNodeIds!.contains(edge.toNodeId);
        if (!isResultEdge) continue;
        final fromNode = graph.getNodeById(edge.fromNodeId);
        final toNode = graph.getNodeById(edge.toNodeId);
        if (fromNode == null || toNode == null) continue;

        final fromCenter = _posForNode(fromNode);
        final toCenter = _posForNode(toNode);
        final fromId = edge.fromNodeId;
        final index = perFromIndex[fromId] ?? 0;
        perFromIndex[fromId] = index + 1;
        final count = perFromCount[fromId] ?? 1;

        var fromPos = _spreadFromPos(
          fromCenter,
          toCenter,
          index,
          count,
          kOnboardingNodeRadius,
        );
        var toPos = _spreadToPos(
          fromCenter,
          toCenter,
          fromPos,
          kOnboardingNodeRadius,
        );

        Offset fromRender = fromPos;
        Offset toRender = toPos;
        if (inSearchResultMode && searchResultIntroAnimation != null) {
          if (resultNodeIds!.contains(fromNode.id)) {
            fromRender =
                fromPos +
                _resultIntroOffsetForNode(
                      node: fromNode,
                      basePos: fromPos,
                      resultsCenter: resultsCenter,
                    ) *
                    introBlend;
          } else if (searchWaveAnimation != null) {
            fromRender =
                fromPos + _waveOffsetForNode(node: fromNode, basePos: fromPos);
          }
          if (resultNodeIds!.contains(toNode.id)) {
            toRender =
                toPos +
                _resultIntroOffsetForNode(
                      node: toNode,
                      basePos: toPos,
                      resultsCenter: resultsCenter,
                    ) *
                    introBlend;
          } else if (searchWaveAnimation != null) {
            toRender = toPos + _waveOffsetForNode(node: toNode, basePos: toPos);
          }
        } else if (searchWaveAnimation != null) {
          fromRender =
              fromPos + _waveOffsetForNode(node: fromNode, basePos: fromPos);
          toRender = toPos + _waveOffsetForNode(node: toNode, basePos: toPos);
        }
        // 메인 canvas와 동일: 결과 엣지는 opacity 1.0 (인트로 적용 없음)
        final edgeOpacity = 1.0;
        _linePaint.color = kOnboardingLineColor.withOpacity(
          (kOnboardingLineOpacity * edgeOpacity).clamp(0.0, 1.0),
        );
        canvas.drawLine(fromRender, toRender, _linePaint);
      }
    }

    // 2. 노드
    final isOnboardingDefault = resultNodeIds == null || resultNodeIds!.isEmpty;
    for (final node in _visibleNodes()) {
      final basePos = _posForNode(node);
      Offset renderPos = basePos;
      if (inSearchResultMode &&
          searchResultIntroAnimation != null &&
          resultNodeIds!.contains(node.id)) {
        renderPos =
            basePos +
            _resultIntroOffsetForNode(
                  node: node,
                  basePos: basePos,
                  resultsCenter: resultsCenter,
                ) *
                introBlend;
      } else if (searchWaveAnimation != null) {
        renderPos = basePos + _waveOffsetForNode(node: node, basePos: basePos);
      }

      final isSearchResultMatch =
          inSearchResultMode && resultNodeIds!.contains(node.id);
      final isSearchResultNonMatch = inSearchResultMode && !isSearchResultMatch;

      Color nodeColor;
      if (isOnboardingDefault) {
        nodeColor = _defaultModeColorForNode(node.id, primaryColor);
      } else if (searchResultExitT != null) {
        final exitT = searchResultExitT!.clamp(0.0, 1.0);
        final normalColor = _defaultModeColorForNode(node.id, primaryColor);
        if (isSearchResultMatch) {
          nodeColor =
              Color.lerp(primaryColor, normalColor, exitT) ?? normalColor;
        } else {
          nodeColor =
              Color.lerp(kOnboardingColorIntensity1, normalColor, exitT) ??
              normalColor;
        }
      } else if (isSearchResultNonMatch) {
        nodeColor = kOnboardingColorIntensity1;
      } else {
        nodeColor =
            isSearchResultMatch
                ? primaryColor
                : _defaultModeColorForNode(node.id, primaryColor);
      }

      double opacity = 0.85;
      if (isOnboardingDefault) {
        // 기본 모드: 전 노드 동일 투명도 (랜덤 색만)
      } else if (inSearchResultMode && isSearchResultNonMatch) {
        // 메인 canvas와 동일: baseFade 0.35 + (1-baseFade)*exitT
        final exitT = searchResultExitT?.clamp(0.0, 1.0) ?? 0.0;
        final baseFade = kOnboardingNonResultOpacity;
        final fade = baseFade + (1.0 - baseFade) * exitT;
        opacity *= fade;
      }
      if (inSearchResultMode && isSearchResultMatch) {
        // 결과 노드는 항상 100% 표시
        opacity *= 1.0;
      }

      double radius;
      if (isOnboardingDefault) {
        radius = kOnboardingDefaultNodeRadius;
      } else if (inSearchResultMode && isSearchResultMatch) {
        final scale = kOnboardingSearchResultNodeScale;
        double resultRadius = kOnboardingDefaultNodeRadius * scale;
        if (searchResultIntroAnimation != null) {
          final t = Curves.easeOutCubic.transform(
            searchResultIntroAnimation!.value.clamp(0.0, 1.0),
          );
          resultRadius *= (0.65 + 0.35 * t);
        }
        if (searchResultExitT != null) {
          final exitT = Curves.easeOutCubic.transform(
            searchResultExitT!.clamp(0.0, 1.0),
          );
          radius =
              resultRadius +
              (kOnboardingDefaultNodeRadius - resultRadius) * exitT;
        } else {
          radius = resultRadius;
        }
      } else {
        radius = kOnboardingDefaultNodeRadius;
      }
      radius = math.max(radius, 10.0);

      _nodePaint.color = nodeColor.withOpacity(opacity);
      canvas.drawCircle(renderPos, radius, _nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant OnboardingGraphPainter old) {
    return old.graph != graph ||
        old.revision != revision ||
        old.primaryColor != primaryColor ||
        old.overridePositions != overridePositions ||
        old.viewport != viewport ||
        old.resultNodeIds != resultNodeIds ||
        old.searchResultExitT != searchResultExitT ||
        old.searchResultIntroAnimation != searchResultIntroAnimation ||
        old.searchWaveAnimation != searchWaveAnimation ||
        old.searchWaveFadeOutT != searchWaveFadeOutT ||
        old.searchWaveIntroT != searchWaveIntroT ||
        old.zoom != zoom;
  }
}
