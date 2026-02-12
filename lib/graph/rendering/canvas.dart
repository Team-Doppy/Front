import 'dart:math' as math;
import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/utils/node_count_utils.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:flutter/material.dart';

enum EdgeRenderMode { all, representativeStar }

class _EdgeDrawItem {
  final GraphEdge edge;
  final GraphNode fromNode;
  final GraphNode toNode;
  _EdgeDrawItem({
    required this.edge,
    required this.fromNode,
    required this.toNode,
  });
}

/// 옵시디언 스타일 그래프 렌더러
/// - 뷰포트 기반 최적화
/// - 클러스터 시각화
/// - 유사도 기반 엣지 스타일링
class GraphPainter extends CustomPainter {
  final GraphData graph;
  final double nodeRadius;
  final Color lineColor;
  final Color primaryColor; // Theme의 primary 색상
  final int? selectedNodeId;
  final int? draggingNodeId;
  final Animation<double>? dragFadeAnimation;
  final int revision;
  final Map<int, Offset>? overridePositions;
  final Rect? viewport; // 현재 뷰포트 (성능 최적화용)
  /// LOD/필터링용: 포함된 노드만 렌더링 (null이면 전체)
  final Set<int>? allowedNodeIds;
  final double zoom; // 현재 줌 레벨
  final Size? screenSize; // 화면 크기 (간선 두께 비례용)
  final int? maxEdges; // similarity 상위 k개만 표시
  final double minEdgeSimilarity; // 유사도 하한 (클러터 방지)
  final int? nodeCount; // 노드 개수 (간선 두께 조정용)
  final EdgeRenderMode edgeRenderMode;
  final int representativeMaxEdgesPerCluster;

  /// 검색 결과 노드 (null이 아니면 비결과 노드 페이드)
  final Set<int>? resultNodeIds;

  /// 온보딩 전용: 비결과 노드 약간 연하게(0.35), 복귀 시 searchResultExitT로 블렌드
  final bool onboardingSearchResult;

  /// 온보딩 전용: 검색결과→일반 복귀 전환 (0=검색결과, 1=일반)
  final double? searchResultExitT;

  /// 검색 중 파도 효과용 애니메이션 (0~1)
  final Animation<double>? searchWaveAnimation;

  /// 검색 결과 인트로 애니메이션 (0~1)
  final Animation<double>? searchResultIntroAnimation;

  /// 드래그 그룹 전체 (root+1hop+2hop) - 이 노드들은 페이드 안 함
  final Set<int>? dragGroupNodeIds;

  /// 키보드 등으로 화면 축소 시 0~1 (1=정상). 노드 변형·축소에 사용
  final double keyboardCompressionFactor;

  GraphPainter({
    required this.graph,
    this.nodeRadius = 8.0, // 이미지처럼 작게
    this.lineColor = Colors.grey,
    required this.primaryColor,
    this.selectedNodeId,
    this.draggingNodeId,
    this.dragFadeAnimation,
    this.revision = 0,
    this.overridePositions,
    this.viewport,
    this.allowedNodeIds,
    this.zoom = 1.0,
    this.screenSize,
    this.maxEdges,
    this.minEdgeSimilarity = 0.0,
    this.nodeCount,
    this.edgeRenderMode = EdgeRenderMode.all,
    this.representativeMaxEdgesPerCluster = 10,
    this.resultNodeIds,
    this.onboardingSearchResult = false,
    this.searchResultExitT,
    this.searchWaveAnimation,
    this.searchResultIntroAnimation,
    this.dragGroupNodeIds,
    this.keyboardCompressionFactor = 1.0,
  }) : super(
         repaint: Listenable.merge(
           <Listenable?>[
             dragFadeAnimation,
             searchWaveAnimation,
             searchResultIntroAnimation,
           ].whereType<Listenable>(),
         ),
       );

  /// Paint 재사용 (GC 부담 감소)
  final Paint _linePaint = Paint()..style = PaintingStyle.stroke;
  final Paint _nodePaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()..style = PaintingStyle.stroke;

  Offset _posForNode(GraphNode node) =>
      overridePositions?[node.id] ?? node.position;

  /// 키보드로 화면 축소 시 노드가 중심 쪽으로 살짝 압축
  Offset _keyboardCompressionOffset(Offset basePos) {
    if (keyboardCompressionFactor >= 1.0) return Offset.zero;
    if (viewport == null) return Offset.zero;
    final cy = viewport!.center.dy;
    final squeeze = (1.0 - keyboardCompressionFactor) * 0.4;
    final dy = (cy - basePos.dy) * squeeze;
    return Offset(0, dy);
  }

  Offset _waveOffsetForNode({
    required GraphNode node,
    required Offset basePos,
  }) {
    final a = searchWaveAnimation;
    if (a == null) return Offset.zero;
    // phase: 0..1 반복
    final phase = a.value;
    // 노드별 시간차(라그): id 기반 + 위치 기반으로 섞어서 자연스러운 파도 느낌
    final lag =
        ((node.id * 0.073) + (basePos.dy * 0.0013) + (basePos.dx * 0.0009));
    final tt = (phase - lag);
    final t = tt - tt.floorToDouble(); // 0..1
    // "위로 밀렸다가 제자리로" (y가 down이므로 음수로 위로)
    // half-sine: 0→1→0
    final wave = math.sin(t * math.pi);
    final amp = (nodeRadius * 1.6).clamp(6.0, 14.0);
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

    // 1) 아래에서 위로 올라오는 느낌 (초기 +y(아래) → 0) - 강하게
    final rise = (38.0 * (1.0 - t));

    // 2) 바깥으로 팡: 중심에서 멀어지는 방향으로 더 크게 이동 + 펀치
    final d = basePos - resultsCenter;
    final dist = d.distance;
    final dir = dist <= 1e-3 ? const Offset(0, -1) : d / dist;
    final settle = 22.0 * t;
    final punch = 14.0 * math.sin(t * math.pi);
    final out = (settle + punch);

    return Offset(dir.dx * out, dir.dy * out + rise);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 뷰포트가 있으면 보이는 영역만 렌더링
    final visibleNodesRaw =
        viewport != null ? _getVisibleNodes(viewport!) : graph.nodes;
    final visibleNodes =
        allowedNodeIds == null
            ? visibleNodesRaw
            : visibleNodesRaw.where((n) => allowedNodeIds!.contains(n.id));

    // 1. 연결선 그리기 (유사도 기반 스타일, zoom에 따른 상위 k개 제한)
    final edgesToDraw = _pickEdgesToDraw();

    final inSearchResultMode = resultNodeIds != null; // 결과 없을 때도 연한 회색 노드 표시
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

    final exitT =
        (searchResultExitT != null) ? searchResultExitT!.clamp(0.0, 1.0) : 0.0;

    // 그릴 엣지 수집 (필터 통과한 것만) → 같은 from 노드별 각도 spread 위해
    final drawList = <_EdgeDrawItem>[];
    for (final edge in edgesToDraw) {
      if (dragGroupNodeIds != null && dragGroupNodeIds!.isNotEmpty) {
        if (!dragGroupNodeIds!.contains(edge.fromNodeId) ||
            !dragGroupNodeIds!.contains(edge.toNodeId))
          continue;
      }
      final isResultEdge =
          resultNodeIds != null &&
          resultNodeIds!.contains(edge.fromNodeId) &&
          resultNodeIds!.contains(edge.toNodeId);
      // 결과가 없을 때는 엣지도 표시 (빈 화면 방지)
      if (inSearchResultMode && resultNodeIds!.isNotEmpty && !isResultEdge) {
        if (exitT <= 0) continue;
      }
      if (allowedNodeIds != null &&
          (!allowedNodeIds!.contains(edge.fromNodeId) ||
              !allowedNodeIds!.contains(edge.toNodeId)))
        continue;
      final fromNode = graph.getNodeById(edge.fromNodeId);
      final toNode = graph.getNodeById(edge.toNodeId);
      if (fromNode == null || toNode == null) continue;
      drawList.add(
        _EdgeDrawItem(edge: edge, fromNode: fromNode, toNode: toNode),
      );
    }
    drawList.sort((a, b) {
      final c = a.edge.fromNodeId.compareTo(b.edge.fromNodeId);
      if (c != 0) return c;
      return a.edge.toNodeId.compareTo(b.edge.toNodeId);
    });
    final perFromCount = <int, int>{};
    for (final item in drawList) {
      final id = item.edge.fromNodeId;
      perFromCount[id] = (perFromCount[id] ?? 0) + 1;
    }
    final perFromIndex = <int, int>{};

    for (final item in drawList) {
      final edge = item.edge;
      final fromNode = item.fromNode;
      final toNode = item.toNode;
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
        nodeRadius,
      );
      var toPos = _spreadToPos(fromCenter, toCenter, fromPos, nodeRadius);

      final introBlend =
          (searchResultExitT != null)
              ? 1.0 - searchResultExitT!.clamp(0.0, 1.0)
              : 1.0;
      Offset fromBase;
      Offset toBase;
      if (inSearchResultMode && searchResultIntroAnimation != null) {
        final fromIntro =
            resultNodeIds!.contains(fromNode.id)
                ? _resultIntroOffsetForNode(
                  node: fromNode,
                  basePos: fromPos,
                  resultsCenter: resultsCenter,
                )
                : Offset.zero;
        final toIntro =
            resultNodeIds!.contains(toNode.id)
                ? _resultIntroOffsetForNode(
                  node: toNode,
                  basePos: toPos,
                  resultsCenter: resultsCenter,
                )
                : Offset.zero;
        fromBase = fromPos + fromIntro * introBlend;
        toBase = toPos + toIntro * introBlend;
      } else {
        fromBase =
            fromPos + _waveOffsetForNode(node: fromNode, basePos: fromPos);
        toBase = toPos + _waveOffsetForNode(node: toNode, basePos: toPos);
      }
      final fromRender = fromBase + _keyboardCompressionOffset(fromBase);
      final toRender = toBase + _keyboardCompressionOffset(toBase);

      final inLod = allowedNodeIds != null;
      final inView =
          viewport == null ||
          _isVisible(fromPos, viewport!) ||
          _isVisible(toPos, viewport!);
      if (inLod || inView) {
        final isResultEdge =
            resultNodeIds != null &&
            resultNodeIds!.contains(edge.fromNodeId) &&
            resultNodeIds!.contains(edge.toNodeId);
        final edgeOpacity =
            (inSearchResultMode && !isResultEdge && exitT > 0) ? exitT : 1.0;
        _drawConnection(
          canvas,
          fromRender,
          toRender,
          edge,
          opacityMultiplier: edgeOpacity,
        );
      }
    }

    // 2. 노드 그리기
    // 검색결과 모드: 모든 노드 그리되, 비결과 노드는 연하게(온보딩·일반 동일)
    final nodesToDraw = visibleNodes;
    final dragNeighbors =
        dragGroupNodeIds != null && dragGroupNodeIds!.isNotEmpty
            ? dragGroupNodeIds!
            : (draggingNodeId != null
                ? _dragNeighborIdsFromEdges(edgesToDraw)
                : <int>{});
    for (final node in nodesToDraw) {
      final basePos = _posForNode(node);
      Offset posWithEffects;
      if (inSearchResultMode && searchResultIntroAnimation != null) {
        final introOffset =
            resultNodeIds!.contains(node.id)
                ? _resultIntroOffsetForNode(
                  node: node,
                  basePos: basePos,
                  resultsCenter: resultsCenter,
                )
                : Offset.zero;
        // 검색결과→일반 복귀 시 인트로 오프셋을 0으로 부드럽게
        final blend =
            (searchResultExitT != null)
                ? 1.0 - searchResultExitT!.clamp(0.0, 1.0)
                : 1.0;
        posWithEffects = basePos + introOffset * blend;
      } else {
        posWithEffects =
            basePos + _waveOffsetForNode(node: node, basePos: basePos);
      }
      final renderPos =
          posWithEffects + _keyboardCompressionOffset(posWithEffects);
      _drawNode(canvas, node, renderPos, dragNeighbors);
    }
  }

  /// 뷰포트 내 보이는 노드만 반환
  List<GraphNode> _getVisibleNodes(Rect viewport) {
    // 여유 공간 추가 (엣지가 잘리지 않도록)
    final expandedViewport = Rect.fromLTRB(
      viewport.left - 100,
      viewport.top - 100,
      viewport.right + 100,
      viewport.bottom + 100,
    );

    return graph.nodes
        .where((node) => expandedViewport.contains(_posForNode(node)))
        .toList();
  }

  bool _isVisible(Offset position, Rect viewport) {
    return viewport.contains(position);
  }

  /// 한 앵커에서 일방향으로 뻗어나가는 엣지만 그림 (fromNode가 isAnchor인 것만)
  Iterable<GraphEdge> _pickEdgesToDraw() {
    return graph.edges.where((e) {
      final from = graph.getNodeById(e.fromNodeId);
      return from != null && from.isAnchor;
    });
  }

  /// 연결선 그리기 (일괄 연하게, similarity/intensity 무관)
  void _drawConnection(
    Canvas canvas,
    Offset start,
    Offset end,
    GraphEdge edge, {
    double opacityMultiplier = 1.0,
  }) {
    // 화면 크기에 비례한 기본 두께 계산
    double baseStrokeWidth = 0.9; // 기본 두께
    if (screenSize != null) {
      // 화면 대각선의 0.15%를 기본 두께로 사용
      final diagonal = math.sqrt(
        screenSize!.width * screenSize!.width +
            screenSize!.height * screenSize!.height,
      );
      baseStrokeWidth = diagonal * 0.1;
    }

    if (nodeCount != null) {
      baseStrokeWidth *= NodeCountUtils.strokeWidthFactor(nodeCount!);
    }

    // 엣지 일괄 연하게 (similarity·intensity 무관)
    var opacity = 0.45 * opacityMultiplier;
    // 최대 축소 모드에서는 엣지 더 연하게
    if (zoom < 0.5) {
      opacity *= (0.45 + 0.2 * (zoom / 0.5).clamp(0.0, 1.0));
    }
    final strokeWidth = baseStrokeWidth * 0.75;

    var w = strokeWidth.clamp(0.3, 1.4) * (1.0 / zoom.clamp(0.6, 5.0));
    // 최대 축소 모드(zoom 작을 때): 엣지 얇게 유지하되 최소 두께는 조금 더 두껍게
    final minStrokeScene =
        zoom < 0.45
            ? (1.5 / zoom.clamp(0.05, 10.0))
            : (2.0 / zoom.clamp(0.05, 10.0));
    w = math.max(w, minStrokeScene);

    _linePaint
      ..color = lineColor.withOpacity(opacity.clamp(0.08, 1.0))
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, _linePaint);
  }

  /// 같은 from 노드에서 나가는 엣지를 각도로 갈라서 시작점 계산 (직선 유지)
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
    final spreadDeg = 2.8;
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

  Set<int> _dragNeighborIdsFromEdges(Iterable<GraphEdge> edges) {
    if (draggingNodeId == null) return {};
    final ids = <int>{};
    for (final e in edges) {
      if (allowedNodeIds != null &&
          (!allowedNodeIds!.contains(e.fromNodeId) ||
              !allowedNodeIds!.contains(e.toNodeId))) {
        continue;
      }
      if (e.fromNodeId == draggingNodeId) ids.add(e.toNodeId);
      if (e.toNodeId == draggingNodeId) ids.add(e.fromNodeId);
    }
    return ids;
  }

  /// intensity: 3=진한색, 2=약간 연함, 1/null=색없는버전(회색)
  static Color _colorForIntensity(Color primary, int? intensity) {
    if (intensity == null || intensity == 1) return Colors.grey.shade400;
    if (intensity == 2) return Color.lerp(primary, Colors.grey.shade400, 0.5)!;
    return primary; // 3
  }

  /// 노드 그리기
  void _drawNode(
    Canvas canvas,
    GraphNode node,
    Offset position,
    Set<int> dragNeighbors,
  ) {
    final isSelected = selectedNodeId == node.id;
    final isDragging = draggingNodeId == node.id;
    final isDragNeighbor = dragNeighbors.contains(node.id);

    final inSearchResultMode = resultNodeIds != null; // 결과 없을 때도 연한 회색 노드 표시
    // 검색 결과 모드: 비결과 노드
    final isSearchResultNonMatch =
        inSearchResultMode && !resultNodeIds!.contains(node.id);
    final isSearchResultMatch = inSearchResultMode && !isSearchResultNonMatch;

    // 드래그 중/해제 시: 드래그 그룹만 유지, 나머지만 연하게 (검색결과 노드는 연해지지 않음)
    final fadeT = dragFadeAnimation?.value ?? 0.0;
    final isAffected =
        fadeT > 0 && !isDragging && !isDragNeighbor && !isSearchResultMatch;

    final baseColor = Colors.grey.shade400;
    final inSearchingMode = searchWaveAnimation != null;

    // intensity: 3=진한색, 2=약간 연함, 1/null=색없는버전(회색)
    final primaryForNode = _colorForIntensity(primaryColor, node.intensity);

    // 기본(드래그/검색 적용 전) 타겟 색
    // - 검색중: 모든 노드 색상 제거(회색)
    // - 검색결과 노드는 intensity 무관 primary 컬러
    // - 그 외는 기존 로직 유지 (public만 컬러)
    final targetColor =
        inSearchingMode
            ? baseColor
            : (isSearchResultMatch
                ? primaryColor
                : (node.isPublic ? primaryForNode : Colors.grey.shade300));

    // 색상은 “뚝” 바뀌지 않도록 fadeT에 따라 부드럽게 보간
    final normalTargetColor =
        inSearchingMode
            ? baseColor
            : (node.isPublic ? primaryForNode : Colors.grey.shade300);
    final Color nodeColor;
    if (searchResultExitT != null) {
      final exitT = searchResultExitT!.clamp(0.0, 1.0);
      if (isSearchResultMatch) {
        nodeColor =
            Color.lerp(primaryColor, normalTargetColor, exitT) ?? primaryColor;
      } else {
        nodeColor =
            Color.lerp(baseColor, normalTargetColor, exitT) ?? baseColor;
      }
    } else if (inSearchResultMode && isSearchResultNonMatch) {
      nodeColor = baseColor;
    } else if (isAffected) {
      nodeColor = Color.lerp(targetColor, baseColor, fadeT) ?? baseColor;
    } else {
      nodeColor = targetColor;
    }

    final baseOpacity = isSelected ? 0.9 : 0.8;
    final fadedOpacity = 0.1;
    double opacity =
        isAffected
            ? baseOpacity + (fadedOpacity - baseOpacity) * fadeT
            : baseOpacity;
    if (inSearchResultMode) {
      if (isAffected) {
        // ✅ 드래그 중에는 결과/비결과 구분 없이 “드래그 그룹 밖”을 동일하게 연하게
        opacity *= 0.15;
      } else if (isSearchResultNonMatch) {
        // 검색결과 비결과: 온보딩·일반 모두 0.35로 연하게
        final baseFade = 0.35;
        double fade = baseFade;
        if (searchResultExitT != null) {
          fade =
              baseFade + (1.0 - baseFade) * searchResultExitT!.clamp(0.0, 1.0);
        }
        opacity *= fade;
      }
    }
    // 검색 중 파도 효과
    // (검색중 파도는 위치 애니메이션으로 처리)

    // 검색 결과 인트로: 결과 노드 페이드인 + 살짝 확대
    if (inSearchResultMode &&
        isSearchResultMatch &&
        searchResultIntroAnimation != null) {
      final tRaw = searchResultIntroAnimation!.value.clamp(0.0, 1.0);
      final t = Curves.easeOutCubic.transform(tRaw);
      opacity *= t;
    }

    double finalRadius = nodeRadius;
    if (inSearchResultMode && isSearchResultMatch) {
      // 검색결과 노드: 기본 1.3배 크기
      const double searchResultScale = 1.3;
      if (searchResultIntroAnimation != null) {
        final tRaw = searchResultIntroAnimation!.value.clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(tRaw);
        finalRadius = nodeRadius * searchResultScale * (0.65 + 0.35 * t);
      } else {
        finalRadius = nodeRadius * searchResultScale;
      }
      if (searchResultExitT != null) {
        final exitT = searchResultExitT!.clamp(0.0, 1.0);
        finalRadius *=
            (1.0 - (searchResultScale - 1) / searchResultScale * exitT);
      }
    }
    // 키보드로 화면 축소 시 노드 사이즈 살짝 축소
    if (keyboardCompressionFactor < 1.0) {
      finalRadius *= (0.88 + 0.12 * keyboardCompressionFactor);
    }
    // 심미 보정: 화면에서 너무 작지 않게 하되, 줌 아웃 시 씬에서 과하게 커져 겹치지 않게 상한
    const double minRadiusPx = 14.0;
    const double maxRadiusScene = 25.0;
    final minRadiusScene = math.min(
      minRadiusPx / zoom.clamp(0.05, 10.0),
      maxRadiusScene,
    );
    finalRadius = math.max(finalRadius, minRadiusScene);

    _nodePaint.color = nodeColor.withOpacity(opacity);

    // 줌인 시에도 “픽셀 두께”가 과도하게 두꺼워지지 않도록 역스케일
    canvas.drawCircle(position, finalRadius, _nodePaint);
    final hideBorder =
        isAffected || (inSearchResultMode && isSearchResultNonMatch);
    if (!hideBorder) {
      _borderPaint
        ..color = isSelected ? nodeColor : nodeColor.withOpacity(0.3)
        ..strokeWidth = (isSelected ? 3.0 : 1.5) * (1.0 / zoom.clamp(0.6, 5.0));
      canvas.drawCircle(position, finalRadius, _borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.draggingNodeId != draggingNodeId ||
        oldDelegate.dragFadeAnimation != dragFadeAnimation ||
        oldDelegate.revision != revision ||
        oldDelegate.viewport != viewport ||
        oldDelegate.allowedNodeIds != allowedNodeIds ||
        oldDelegate.resultNodeIds != resultNodeIds ||
        oldDelegate.onboardingSearchResult != onboardingSearchResult ||
        oldDelegate.searchResultExitT != searchResultExitT ||
        oldDelegate.searchWaveAnimation != searchWaveAnimation ||
        oldDelegate.searchResultIntroAnimation != searchResultIntroAnimation ||
        oldDelegate.dragGroupNodeIds != dragGroupNodeIds ||
        oldDelegate.keyboardCompressionFactor != keyboardCompressionFactor ||
        oldDelegate.zoom != zoom ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.maxEdges != maxEdges ||
        oldDelegate.minEdgeSimilarity != minEdgeSimilarity ||
        oldDelegate.nodeCount != nodeCount ||
        oldDelegate.overridePositions != overridePositions;
  }
}
