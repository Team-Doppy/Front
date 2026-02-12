import 'dart:math' as math;
import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:flutter/material.dart';

/// 개선된 Force-Directed 레이아웃 알고리즘
/// - 노드 겹침 완전 방지
/// - 줌 레벨에 따른 동적 거리 조정
/// - 모바일 최적화
class ForceDirectedLayout {
  static const double _coolingFactor = 0.95; // 냉각 계수
  static const double _initialTemperature = 100.0;
  static const double _minDistanceFactor =
      2.7; // nodePadding * factor = min distance (겹침 방지용으로 여유 있게)

  static double _wrapToPi(double a) {
    // (-pi, pi]
    var x = a;
    while (x <= -math.pi) x += 2 * math.pi;
    while (x > math.pi) x -= 2 * math.pi;
    return x;
  }

  /// 노드 수에 따라 동적으로 노드 간격 계산 (겹치지 않게 여유 있는 배치)
  static double _getNodePadding(int nodeCount) {
    if (nodeCount <= 10) return 44.0;
    if (nodeCount <= 30) return 38.0;
    if (nodeCount <= 50) return 34.0;
    if (nodeCount <= 80) return 32.0;
    if (nodeCount <= 120) return 32.0;
    if (nodeCount <= 200) return 29.0;
    return 27.0; // 200개 이상
  }

  static double minNodeDistance(int nodeCount) =>
      _getNodePadding(nodeCount) * _minDistanceFactor;

  /// 엣지에 등장하는 노드 ID (그래프에 존재하는 것만). 독립 노드 판별용
  static Set<int> _edgeConnectedNodeIds(GraphData graph) {
    final ids = <int>{};
    for (final e in graph.edges) {
      if (graph.getNodeById(e.fromNodeId) != null) ids.add(e.fromNodeId);
      if (graph.getNodeById(e.toNodeId) != null) ids.add(e.toNodeId);
    }
    return ids;
  }

  /// 노드 수에 비례해 “충분히 큰” 월드 사이즈를 제안
  /// - world가 너무 작으면 밀린 노드가 경계에 clamp되며 “끝에 줄서기”가 발생함
  /// - 초기 배치를 더 조밀하게 하기 위해 world size를 줄임
  static Size suggestWorldSize({
    required Size screenSize,
    required int nodeCount,
  }) {
    final d = minNodeDistance(nodeCount);
    // 넓직하게: 화면 밖으로 벗어나도 되므로 베이스를 2배 이상으로
    final base = math.max(screenSize.width, screenSize.height) * 2.2;
    final areaFactor =
        nodeCount >= 80
            ? 9.5 + 0.07 * (nodeCount - 80).clamp(0, 300)
            : 5.0 + 0.05 * nodeCount.clamp(1, 79);
    final area = nodeCount * d * d * areaFactor;
    final side = math.sqrt(area);

    final screenAspect =
        screenSize.width <= 0 ? 1.0 : (screenSize.height / screenSize.width);
    // 세로로 너무 길지 않게: 비율 상한 (가로 대비 세로 최대 1.25)
    final aspect = math.min(screenAspect, 1.25);

    final w = math.max(base, side);
    final h = math.max(base * aspect, side * aspect);
    return Size(w, h);
  }

  /// 최초 1회: 초기 배치 (균등 분산)
  /// - 줌 변경 때마다 재초기화하면 “프레지 느낌”이 아니라 “리셋”처럼 보이므로 분리함
  static void initialize(GraphData graph, {required Size worldSize}) {
    if (graph.nodes.isEmpty) return;
    _initialPlacement(graph, worldSize);
    resolveCollisions(graph, worldSize: worldSize);
  }

  /// 서버 position 참고 후, 단순 심미 보정: 레이아웃을 월드에 맞춰 스케일·중앙 정렬만 (왜곡 없음)
  static void applyAestheticDistribution(
    GraphData graph, {
    required Size worldSize,
  }) {
    final nodes = graph.nodes;
    if (nodes.length <= 1) return;

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final n in nodes) {
      if (n.position.dx < minX) minX = n.position.dx;
      if (n.position.dx > maxX) maxX = n.position.dx;
      if (n.position.dy < minY) minY = n.position.dy;
      if (n.position.dy > maxY) maxY = n.position.dy;
    }
    final boxW = (maxX - minX).clamp(1.0, double.infinity);
    final boxH = (maxY - minY).clamp(1.0, double.infinity);
    final layoutCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final worldCenter = Offset(worldSize.width / 2, worldSize.height / 2);
    // 비율 유지한 채 월드의 88% 안에 맞추기 (한쪽만 채우면 빈 공간 생김 → min 사용)
    final scale = math
        .min((worldSize.width * 0.88) / boxW, (worldSize.height * 0.88) / boxH)
        .clamp(0.01, 15.0);
    for (final n in nodes) {
      n.position = worldCenter + (n.position - layoutCenter) * scale;
      _keepInWorld(n, worldSize, nodes.length);
    }
    resolveCollisions(graph, worldSize: worldSize);
  }

  /// 점진적 안정화(Force-Directed)
  /// - 초기화 이후 “조금만” 다듬는 용도
  static void relax(
    GraphData graph, {
    required Size worldSize,
    double zoom = 1.0,
    int? iterations,
  }) {
    if (graph.nodes.isEmpty) return;
    final it = iterations ?? _getIterations(graph.nodes.length);
    _simulate(graph, worldSize, it, zoom);
  }

  /// 프레지 느낌: 특정 포커스를 중심으로 노드들을 “더 멀어지게” 확장
  /// - factor > 1이면 멀어짐, factor < 1이면 모임
  static void expandAroundFocus(
    GraphData graph, {
    required Offset focus,
    required double factor,
    required Size worldSize,
  }) {
    if (graph.nodes.isEmpty) return;
    for (final node in graph.nodes) {
      final d = node.position - focus;
      node.position = focus + d * factor;
      _keepInWorld(node, worldSize, graph.nodes.length);
    }
    resolveCollisions(graph, worldSize: worldSize);
  }

  /// 노드 수에 따른 반복 횟수 (겹침 해소를 위해 충분히)
  static int _getIterations(int nodeCount) {
    if (nodeCount < 20) return 80;
    if (nodeCount < 50) return 110;
    if (nodeCount < 100) return 140;
    if (nodeCount < 200) return 170;
    return 200;
  }

  /// 초기 배치: layoutHint → 시드, 없으면 앵커는 원형·나머지는 앵커 주변/클러스터별 그리드
  /// - c(클러스터), a(앵커), orderInCluster로 의미 있는 분포 시드
  static void _initialPlacement(GraphData graph, Size worldSize) {
    final random = math.Random(42);
    final nodeCount = graph.nodes.length;
    final centerX = worldSize.width / 2;
    final centerY = worldSize.height / 2;
    final halfW = worldSize.width * 0.44;
    final halfH = worldSize.height * 0.44;
    final nodePadding = _getNodePadding(nodeCount);
    final clusterWidth = worldSize.width * 0.78;
    final clusterHeight = worldSize.height * 0.78;

    // 1) layoutHint 있는 노드: 기존처럼 정규화 후 배치
    double minDx = double.infinity, maxDx = -double.infinity;
    double minDy = double.infinity, maxDy = -double.infinity;
    var hasHint = false;
    for (final node in graph.nodes) {
      final h = node.layoutHint;
      if (h != null) {
        hasHint = true;
        if (h.dx < minDx) minDx = h.dx;
        if (h.dx > maxDx) maxDx = h.dx;
        if (h.dy < minDy) minDy = h.dy;
        if (h.dy > maxDy) maxDy = h.dy;
      }
    }
    final spanX = (maxDx - minDx).abs();
    final spanY = (maxDy - minDy).abs();
    final isPixelLike =
        spanX > 2.5 ||
        spanY > 2.5 ||
        maxDx > 1.5 ||
        minDx < -1.5 ||
        maxDy > 1.5 ||
        minDy < -1.5;
    final isZeroToOne =
        (minDx >= 0 && maxDx <= 1) || (minDy >= 0 && maxDy <= 1);
    final needNorm = hasHint && (isPixelLike || isZeroToOne);

    for (final node in graph.nodes) {
      if (node.layoutHint != null) {
        var dx = node.layoutHint!.dx;
        var dy = node.layoutHint!.dy;
        if (needNorm && spanX > 1e-6 && spanY > 1e-6) {
          dx = (dx - minDx) / spanX * 2 - 1;
          dy = (dy - minDy) / spanY * 2 - 1;
        } else if (needNorm && (spanX <= 1e-6 || spanY <= 1e-6)) {
          dx = spanX <= 1e-6 ? 0.0 : (dx - minDx) / spanX * 2 - 1;
          dy = spanY <= 1e-6 ? 0.0 : (dy - minDy) / spanY * 2 - 1;
        }
        node.position = Offset(centerX + dx * halfW, centerY + dy * halfH);
        _keepInWorld(node, worldSize, nodeCount);
      }
    }

    // 2) hint 없는 노드: 앵커 → 원형, 비앵커 → 앵커 주변 또는 클러스터순 그리드
    final rest = graph.nodes.where((n) => n.layoutHint == null).toList();
    if (rest.isEmpty) return;

    final anchors = rest.where((n) => n.isAnchor).toList();
    final others =
        rest.where((n) => !n.isAnchor).toList()..sort((a, b) {
          final ca = a.clusterId ?? -1;
          final cb = b.clusterId ?? -1;
          if (ca != cb) return ca.compareTo(cb);
          final oa = a.orderInCluster ?? 0;
          final ob = b.orderInCluster ?? 0;
          if (oa != ob) return oa.compareTo(ob);
          return a.id.compareTo(b.id);
        });

    // 앵커를 중앙 근처에 배치 (동공 생기지 않게 큰 원 X → 작은 반경으로 중앙 쪽)
    final anchorRadius = math.min(halfW, halfH) * 0.24;
    for (var i = 0; i < anchors.length; i++) {
      final angle = 2 * math.pi * i / math.max(1, anchors.length);
      anchors[i].position = Offset(
        centerX + anchorRadius * math.cos(angle),
        centerY + anchorRadius * math.sin(angle),
      );
      _keepInWorld(anchors[i], worldSize, nodeCount);
    }

    final edgeConnectedIds = _edgeConnectedNodeIds(graph);
    final withEdge =
        others.where((n) => edgeConnectedIds.contains(n.id)).toList();
    final independent =
        others.where((n) => !edgeConnectedIds.contains(n.id)).toList();

    // 엣지 연결 노드: anchorId 있으면 앵커 주변 링, 없으면 클러스터순 그리드
    var gridIndex = 0;
    final countWithEdge = withEdge.length;
    final cols = math.sqrt(countWithEdge).ceil();
    final rows = (countWithEdge / cols).ceil();
    final cellWidth = clusterWidth / cols;
    final cellHeight = clusterHeight / rows;

    for (final node in withEdge) {
      final anchor =
          node.anchorId != null ? graph.getNodeById(node.anchorId!) : null;
      final anchorPlaced =
          anchor != null &&
          (anchor.position.dx != 0 || anchor.position.dy != 0);

      if (anchorPlaced) {
        final r = nodePadding * 2.4 * (0.9 + random.nextDouble() * 0.4);
        final theta = random.nextDouble() * 2 * math.pi;
        node.position =
            anchor.position + Offset(r * math.cos(theta), r * math.sin(theta));
      } else {
        final row = gridIndex ~/ cols;
        final col = gridIndex % cols;
        final baseX = centerX - clusterWidth / 2 + cellWidth * (col + 0.5);
        final baseY = centerY - clusterHeight / 2 + cellHeight * (row + 0.5);
        node.position = Offset(
          baseX + (random.nextDouble() - 0.5) * cellWidth * 0.3,
          baseY + (random.nextDouble() - 0.5) * cellHeight * 0.3,
        );
        gridIndex++;
      }
      _keepInWorld(node, worldSize, nodeCount);
    }

    // 독립 노드: 연결 영역 바깥 링이지만 너무 멀리 않게 (구분 느낌만)
    final outerRadius = math.min(halfW, halfH) * 0.76;
    for (var i = 0; i < independent.length; i++) {
      final angle =
          2 * math.pi * i / math.max(1, independent.length) +
          random.nextDouble() * 0.2;
      independent[i].position = Offset(
        centerX + outerRadius * math.cos(angle),
        centerY + outerRadius * math.sin(angle),
      );
      _keepInWorld(independent[i], worldSize, nodeCount);
    }
  }

  /// Force-directed 시뮬레이션
  static void _simulate(
    GraphData graph,
    Size worldSize,
    int iterations,
    double zoom,
  ) {
    // 줌 레벨에 따른 기본 거리 조정
    final baseDistance = _calculateBaseDistance(worldSize, zoom);

    // 초기 온도
    double temperature = _initialTemperature;

    final nodes = graph.nodes;
    final n = nodes.length;
    final idToIndex = <int, int>{};
    for (int i = 0; i < n; i++) {
      idToIndex[nodes[i].id] = i;
    }

    final center = Offset(worldSize.width / 2, worldSize.height / 2);
    final nodePadding = _getNodePadding(n);
    final minDist = nodePadding * _minDistanceFactor;
    final cellSize = minDist * 1.35;
    final edgeConnectedIds = _edgeConnectedNodeIds(graph);

    // --- precompute: anchor(=from)별 등각 슬롯 목표(각도) ---
    // 무게중심과 충돌하지 않도록 “강제 배치”가 아니라 “회전(탄젠셜) 스프링”으로 각도만 유지한다.
    final outToIdx = <int, List<int>>{};
    for (final e in graph.edges) {
      final fi = idToIndex[e.fromNodeId];
      final ti = idToIndex[e.toNodeId];
      if (fi == null || ti == null) continue;
      outToIdx.putIfAbsent(fi, () => []).add(ti);
    }
    final anchorTargets = <int, List<(int toIdx, double angle)>>{};
    for (final entry in outToIdx.entries) {
      final fromIdx = entry.key;
      final tos = entry.value;
      if (tos.length < 3) continue;
      // 안정적인 슬롯 매핑: orderInCluster -> id
      tos.sort((a, b) {
        final na = nodes[a];
        final nb = nodes[b];
        final oa = na.orderInCluster ?? 0;
        final ob = nb.orderInCluster ?? 0;
        if (oa != ob) return oa.compareTo(ob);
        return na.id.compareTo(nb.id);
      });
      final k = tos.length;
      // 현재 배치 기준으로 슬롯 전체를 회전시켜 “기존 방향감”을 유지
      final fromPos = nodes[fromIdx].position;
      double sumSin = 0.0, sumCos = 0.0;
      for (var i = 0; i < k; i++) {
        final base = 2 * math.pi * i / k;
        final v = nodes[tos[i]].position - fromPos;
        final cur = math.atan2(v.dy, v.dx);
        final diff = _wrapToPi(cur - base);
        sumSin += math.sin(diff);
        sumCos += math.cos(diff);
      }
      final rot = math.atan2(sumSin, sumCos);
      anchorTargets[fromIdx] = [
        for (var i = 0; i < k; i++) (tos[i], 2 * math.pi * i / k + rot),
      ];
    }

    for (int iter = 0; iter < iterations; iter++) {
      // forces: index 기반 (빠름)
      final forces = List<Offset>.filled(n, Offset.zero);

      // 1. 엣지 인력 (유사도 기반)
      for (final edge in graph.edges) {
        final fromIdx = idToIndex[edge.fromNodeId];
        final toIdx = idToIndex[edge.toNodeId];
        if (fromIdx == null || toIdx == null) continue;
        final fromNode = nodes[fromIdx];
        final toNode = nodes[toIdx];

        final delta = toNode.position - fromNode.position;
        final distance = delta.distance;

        if (distance > 0) {
          // 엣지 짧게: 같은 클러스터 더 짧게, 클러스터 간도 최소 거리로 당겨서 마주보게
          final baseIdeal =
              baseDistance * 0.36 * (0.5 + 0.4 * (1.0 - edge.similarity));
          final sameCluster =
              fromNode.clusterId != null &&
              fromNode.clusterId == toNode.clusterId;
          final idealDistance =
              sameCluster
                  ? baseIdeal * 0.6
                  : baseIdeal * 0.55; // 클러스터 간: 최단 거리로 당김
          final diff = distance - idealDistance;
          final attraction = diff * 0.22 * (0.3 + edge.similarity);
          final normalized = delta / distance;
          forces[fromIdx] = forces[fromIdx] + normalized * attraction;
          forces[toIdx] = forces[toIdx] - normalized * attraction;
        }
      }

      // 1.5 같은 클러스터(c)끼리 묶이도록 centroid 인력
      final clusterSum = <int, Offset>{};
      final clusterCount = <int, int>{};
      for (int i = 0; i < n; i++) {
        final c = nodes[i].clusterId;
        if (c == null) continue;
        clusterSum[c] = (clusterSum[c] ?? Offset.zero) + nodes[i].position;
        clusterCount[c] = (clusterCount[c] ?? 0) + 1;
      }
      for (int i = 0; i < n; i++) {
        final c = nodes[i].clusterId;
        if (c == null) continue;
        final count = clusterCount[c] ?? 1;
        final centroid = clusterSum[c]! / count.toDouble();
        final toCentroid = centroid - nodes[i].position;
        final dist = toCentroid.distance;
        if (dist > 1.0) {
          forces[i] = forces[i] + toCentroid * (0.018 / dist);
        }
      }

      // 1.6 앵커(a) 방향 인력: anchorId 있으면 해당 앵커 쪽으로
      for (int i = 0; i < n; i++) {
        final aid = nodes[i].anchorId;
        if (aid == null) continue;
        final anchorIdx = idToIndex[aid];
        if (anchorIdx == null) continue;
        final toAnchor = nodes[anchorIdx].position - nodes[i].position;
        final dist = toAnchor.distance;
        if (dist > 1.0) {
          forces[i] = forces[i] + toAnchor * (0.045 / dist);
        }
      }

      // 1.7 무게중심(이웃 중심) 스프링: 2갈래 이상 노드는 이웃들의 무게중심으로 끌어당김
      // (등각과 충돌하지 않도록 “post-pass 덮어쓰기”가 아니라 forces로 함께 수렴)
      final sumN = List<Offset>.filled(n, Offset.zero);
      final cntN = List<int>.filled(n, 0);
      for (final e in graph.edges) {
        final fi = idToIndex[e.fromNodeId];
        final ti = idToIndex[e.toNodeId];
        if (fi == null || ti == null) continue;
        sumN[fi] = sumN[fi] + nodes[ti].position;
        cntN[fi] += 1;
        sumN[ti] = sumN[ti] + nodes[fi].position;
        cntN[ti] += 1;
      }
      const kBary = 0.06; // 무게중심 힘 (조절)
      for (var i = 0; i < n; i++) {
        if (nodes[i].isAnchor) continue;
        if (cntN[i] < 2) continue;
        final centroid = sumN[i] / cntN[i].toDouble();
        final d = centroid - nodes[i].position;
        forces[i] = forces[i] + d * kBary;
      }

      // 1.8 등각(각도) 스프링: 앵커에서 나가는 엣지 방향을 등각 슬롯에 “회전”으로 맞춤(반지름은 그대로)
      const kAngle = 0.10; // 각도 스프링 강도 (조절)
      for (final entry in anchorTargets.entries) {
        final fromIdx = entry.key;
        final fromPos = nodes[fromIdx].position;
        for (final pair in entry.value) {
          final toIdx = pair.$1;
          final targetAngle = pair.$2;
          final v = nodes[toIdx].position - fromPos;
          final r = v.distance;
          if (r <= 1e-6) continue;
          final cur = math.atan2(v.dy, v.dx);
          final diff = _wrapToPi(targetAngle - cur);
          // 탄젠셜 방향(회전)으로만 힘 적용 → 무게중심/거리 힘과 공존
          final tDir = Offset(-v.dy / r, v.dx / r);
          final arc = diff * r; // 각도 오차를 호 길이로
          final f = tDir * (arc * kAngle);
          forces[toIdx] = forces[toIdx] + f;
          forces[fromIdx] = forces[fromIdx] - f * 0.08; // 앵커는 조금만 반작용
        }
      }

      // 2. 노드 반발/충돌 (공간 해시로 근접 이웃만 계산: O(N))
      final buckets = _buildBuckets(nodes, cellSize);
      for (int i = 0; i < n; i++) {
        final p = nodes[i].position;
        final cx = (p.dx / cellSize).floor();
        final cy = (p.dy / cellSize).floor();

        for (int ox = -1; ox <= 1; ox++) {
          for (int oy = -1; oy <= 1; oy++) {
            final key = _bucketKey(cx + ox, cy + oy);
            final list = buckets[key];
            if (list == null) continue;

            for (final j in list) {
              if (j <= i) continue; // pair once
              final q = nodes[j].position;
              final delta = q - p;
              final dist = delta.distance;
              if (dist <= 0) continue;

              final normalized = delta / dist;

              if (dist < minDist) {
                // 강한 충돌 반발 (겹침 방지)
                final rep = ((minDist - dist) / minDist) * 95.0;
                forces[i] = forces[i] - normalized * rep;
                forces[j] = forces[j] + normalized * rep;
              } else {
                // 같은 클러스터 안: 간격 넉넉히. 다른 클러스터끼리도 더 밀어서 겹침 감소
                final sameCluster =
                    nodes[i].clusterId != null &&
                    nodes[i].clusterId == nodes[j].clusterId;
                final rep =
                    sameCluster ? 32.0 / (dist * dist) : 16.0 / (dist * dist);
                forces[i] = forces[i] - normalized * rep;
                forces[j] = forces[j] + normalized * rep;
              }
            }
          }
        }
      }

      // 2.5 gravity: 연결 노드는 중앙으로 약하게, 독립 노드는 연결 영역 밖으로 밀어냄
      double sumCx = 0, sumCy = 0;
      var connectedCount = 0;
      for (int i = 0; i < n; i++) {
        if (edgeConnectedIds.contains(nodes[i].id)) {
          sumCx += nodes[i].position.dx;
          sumCy += nodes[i].position.dy;
          connectedCount++;
        }
      }
      final connectedCentroid =
          connectedCount > 0
              ? Offset(sumCx / connectedCount, sumCy / connectedCount)
              : center;
      for (int i = 0; i < n; i++) {
        if (edgeConnectedIds.contains(nodes[i].id)) {
          // 중앙으로 당겨서 동공(가운데 빈 공간) 생기지 않게
          final toCenter = center - nodes[i].position;
          forces[i] = forces[i] + toCenter * 0.013;
        } else {
          // 독립 노드: 연결 영역 바깥으로 살짝만 (완전 분리보다는 구분 느낌)
          final fromCentroid = nodes[i].position - connectedCentroid;
          final dist = fromCentroid.distance;
          if (dist > 1.0) {
            forces[i] = forces[i] + fromCentroid * (0.02 / dist);
          }
        }
      }

      // 3. 위치 업데이트 (온도 기반 제한)
      for (int i = 0; i < n; i++) {
        var force = forces[i];
        final forceMagnitude = force.distance;

        // 온도로 힘 제한 (과도한 이동 방지)
        if (forceMagnitude > temperature && forceMagnitude > 0) {
          force = force / forceMagnitude * temperature;
        }

        // 위치 업데이트
        nodes[i].position = nodes[i].position + force;
        _keepInWorld(nodes[i], worldSize, n);
      }

      // 온도 감소 (시뮬레이션 안정화)
      temperature *= _coolingFactor;
    }

    // 클러스터 간 엣지(1~2개만 있는 from 포함): 최소 거리로 당겨서 양 끝이 마주보게
    _pullInterClusterEdgesToMinimum(graph, worldSize);

    // 개별 노드가 어떤 엣지 위에도 겹치지 않도록 밀어냄
    _pushNodesOffEdges(graph, worldSize);

    // 최종 충돌 검사 및 수정
    resolveCollisions(graph, worldSize: worldSize);
  }

  /// 엣지 선분 위(또는 너무 가까이)에 있는 노드를 수직 방향으로 밀어냄
  static void _pushNodesOffEdges(GraphData graph, Size worldSize) {
    final nodes = graph.nodes;
    final n = nodes.length;
    if (n <= 2 || graph.edges.isEmpty) return;
    final minOffEdge = minNodeDistance(n) * 0.55;
    const maxPasses = 4;
    final minOffEdge2 = minOffEdge * minOffEdge;

    for (var pass = 0; pass < maxPasses; pass++) {
      var moved = false;
      // 엣지 주변 노드만 보도록 공간 해시 사용 (O(E·N) → 근접 후보만)
      final cellSize = minOffEdge * 1.4;
      final buckets = _buildBuckets(nodes, cellSize);
      final idToIndex = <int, int>{};
      for (var i = 0; i < n; i++) {
        idToIndex[nodes[i].id] = i;
      }

      for (final edge in graph.edges) {
        final fromIdx = idToIndex[edge.fromNodeId];
        final toIdx = idToIndex[edge.toNodeId];
        if (fromIdx == null || toIdx == null) continue;
        final a = nodes[fromIdx].position;
        final b = nodes[toIdx].position;
        final ab = b - a;
        final L2 = ab.dx * ab.dx + ab.dy * ab.dy;
        if (L2 <= 1e-6) continue;

        final minX = math.min(a.dx, b.dx) - minOffEdge;
        final maxX = math.max(a.dx, b.dx) + minOffEdge;
        final minY = math.min(a.dy, b.dy) - minOffEdge;
        final maxY = math.max(a.dy, b.dy) + minOffEdge;
        final cMinX = (minX / cellSize).floor();
        final cMaxX = (maxX / cellSize).floor();
        final cMinY = (minY / cellSize).floor();
        final cMaxY = (maxY / cellSize).floor();

        for (var cx = cMinX; cx <= cMaxX; cx++) {
          for (var cy = cMinY; cy <= cMaxY; cy++) {
            final list = buckets[_bucketKey(cx, cy)];
            if (list == null) continue;
            for (final idx in list) {
              if (idx == fromIdx || idx == toIdx) continue;
              final c = nodes[idx].position;

              // closest point on segment
              final ac = c - a;
              final t = ((ac.dx * ab.dx + ac.dy * ab.dy) / L2).clamp(0.0, 1.0);
              final closest = a + Offset(ab.dx * t, ab.dy * t);
              final dc = c - closest;
              final dist2 = dc.dx * dc.dx + dc.dy * dc.dy;
              if (dist2 >= minOffEdge2) continue;

              moved = true;
              if (dist2 <= 1e-6) {
                final invL = 1.0 / math.sqrt(L2);
                nodes[idx].position =
                    closest + Offset(-ab.dy * invL, ab.dx * invL) * minOffEdge;
              } else {
                final dist = math.sqrt(dist2);
                final pushDir = dc / dist;
                nodes[idx].position = closest + pushDir * minOffEdge;
              }
              _keepInWorld(nodes[idx], worldSize, n);
            }
          }
        }
      }
      if (!moved) break;
    }
  }

  /// 클러스터 간 엣지 중 from이 엣지 1~2개만 가진 경우: 최소 거리로 당겨서 마주보게 (3개 이상은 위에서 이미 처리)
  static void _pullInterClusterEdgesToMinimum(GraphData graph, Size worldSize) {
    final n = graph.nodes.length;
    if (n <= 1 || graph.edges.isEmpty) return;
    final outDegree = <int, int>{};
    for (final e in graph.edges) {
      outDegree[e.fromNodeId] = (outDegree[e.fromNodeId] ?? 0) + 1;
    }
    final minLen = minNodeDistance(n) * 0.95;

    for (final edge in graph.edges) {
      if ((outDegree[edge.fromNodeId] ?? 0) >= 3) continue;
      final from = graph.getNodeById(edge.fromNodeId);
      final to = graph.getNodeById(edge.toNodeId);
      if (from == null || to == null) continue;
      final sameCluster =
          from.clusterId != null &&
          to.clusterId != null &&
          from.clusterId == to.clusterId;
      if (sameCluster) continue;

      final delta = to.position - from.position;
      final dist = delta.distance;
      if (dist <= 0) continue;
      final dir = delta / dist;
      final targetLen = dist > minLen ? minLen : dist;
      to.position = from.position + dir * targetLen;
      _keepInWorld(to, worldSize, n);
    }
  }

  /// 줌 레벨에 따른 기본 거리 계산
  static double _calculateBaseDistance(Size worldSize, double zoom) {
    // 화면 대각선의 일정 비율을 기본 거리로 사용
    final baseDiagonal = math.sqrt(
      worldSize.width * worldSize.width + worldSize.height * worldSize.height,
    );

    // “줌하면 더 멀어지는” 느낌을 위해 선형보다 조금 더 강하게
    // (InteractiveViewer 자체 스케일과 별개로, 월드 좌표도 함께 확장)
    final baseDistance = baseDiagonal * 0.10;
    final zoomBoost = math.pow(zoom.clamp(0.1, 5.0), 1.15).toDouble();
    return baseDistance * zoomBoost;
  }

  /// hard clamp 대신 “반사(reflect)”로 월드 안에 유지
  /// - clamp만 쓰면 많은 노드가 경계에 붙어 “끝에 줄서기”가 생김
  static void _keepInWorld(GraphNode node, Size worldSize, int nodeCount) {
    final margin = _getNodePadding(nodeCount);
    double x = node.position.dx;
    double y = node.position.dy;

    final minX = margin;
    final maxX = worldSize.width - margin;
    final minY = margin;
    final maxY = worldSize.height - margin;

    if (x < minX) x = minX + (minX - x);
    if (x > maxX) x = maxX - (x - maxX);
    if (y < minY) y = minY + (minY - y);
    if (y > maxY) y = maxY - (y - maxY);

    // 그래도 범위 밖이면 마지막으로 clamp
    node.position = Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
  }

  static Map<int, List<int>> _buildBuckets(
    List<GraphNode> nodes,
    double cellSize,
  ) {
    final buckets = <int, List<int>>{};
    for (int i = 0; i < nodes.length; i++) {
      final p = nodes[i].position;
      final cx = (p.dx / cellSize).floor();
      final cy = (p.dy / cellSize).floor();
      final key = _bucketKey(cx, cy);
      (buckets[key] ??= <int>[]).add(i);
    }
    return buckets;
  }

  static int _bucketKey(int cx, int cy) {
    // cx,cy는 0 이상이 일반적이지만 안전하게 & mask
    final x = cx & 0xFFFFF;
    final y = cy & 0xFFFFF;
    return (x << 20) ^ y;
  }

  /// 최종 충돌 해결 (강제 분리) - 외부에서도 호출 가능
  static void resolveCollisions(GraphData graph, {required Size worldSize}) {
    final nodes = graph.nodes;
    final n = nodes.length;
    if (n <= 1) return;

    final minDist = minNodeDistance(n);
    final cellSize = minDist * 1.35;
    final maxIterations = 28;

    for (int iter = 0; iter < maxIterations; iter++) {
      bool moved = false;
      final buckets = _buildBuckets(nodes, cellSize);

      for (int i = 0; i < n; i++) {
        final p = nodes[i].position;
        final cx = (p.dx / cellSize).floor();
        final cy = (p.dy / cellSize).floor();

        for (int ox = -1; ox <= 1; ox++) {
          for (int oy = -1; oy <= 1; oy++) {
            final list = buckets[_bucketKey(cx + ox, cy + oy)];
            if (list == null) continue;
            for (final j in list) {
              if (j <= i) continue;
              final q = nodes[j].position;
              final delta = q - p;
              final dist = delta.distance;
              if (dist <= 0 || dist >= minDist) continue;

              moved = true;
              final normalized = delta / dist;
              final separation = (minDist - dist) / 2;
              nodes[i].position = nodes[i].position - normalized * separation;
              nodes[j].position = nodes[j].position + normalized * separation;
              _keepInWorld(nodes[i], worldSize, n);
              _keepInWorld(nodes[j], worldSize, n);
            }
          }
        }
      }

      if (!moved) break;
    }
  }

  /// 레이아웃 완료 후 위치에 약간의 불규칙성 추가 (온보딩 등)
  /// [amount]: minNodeDistance 대비 오프셋 비율 (0.1~0.2 권장)
  static void addPositionJitter(
    GraphData graph,
    Size worldSize, {
    double amount = 0.12,
  }) {
    final nodes = graph.nodes;
    final n = nodes.length;
    if (n <= 0 || amount <= 0) return;
    final random = math.Random(42);
    final jitter = minNodeDistance(n) * amount;
    for (final node in nodes) {
      final dx = (random.nextDouble() * 2 - 1) * jitter;
      final dy = (random.nextDouble() * 2 - 1) * jitter;
      node.position = node.position + Offset(dx, dy);
      _keepInWorld(node, worldSize, n);
    }
    resolveCollisions(graph, worldSize: worldSize);
  }
}
