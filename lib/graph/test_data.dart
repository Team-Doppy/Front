import 'dart:math' as math;
import 'dart:ui';
import 'package:doppy/graph/models/node.dart';
import 'package:doppy/graph/models/edge.dart';

/// 테스트 데이터 생성 클래스
class TestData {
  final int numOfNodes;
  final int kNeighbors; // 각 노드당 연결할 “비슷한 노드” 개수 (핵심)
  final int? clusterCount; // null이면 자동
  final double minSimilarity; // 최소 유사도 임계값 (필터)
  final double crossClusterRate; // 클러스터간 연결 비율 (거의 0 권장)
  /// true면 노드를 원형으로 분포 (온보딩용)
  final bool circularLayout;

  /// circularLayout일 때 이중 링(안쪽/바깥쪽) 분포
  final bool circularDoubleRing;

  /// 앵커 최소 개수 (0, n/3, 2n/3... 에 배치)
  final int minAnchors;

  TestData({
    this.numOfNodes = 1000,
    this.kNeighbors = 3,
    this.clusterCount,
    this.minSimilarity = 0.55,
    this.crossClusterRate = 0.02,
    this.circularLayout = false,
    this.circularDoubleRing = false,
    this.minAnchors = 0,
  });

  /// GraphData 생성 (노드 + 엣지)
  GraphData generateGraphData() {
    final random = math.Random(42); // 시드 고정 (재현 가능)
    final latent =
        circularLayout
            ? _generateCircularLatentPoints(random)
            : _generateLatentPoints(random);
    final nodes = _generateNodes(random, latent);
    final edges = _generateSparseEdges(random, nodes, latent);
    return GraphData(nodes: nodes, edges: edges);
  }

  /// (내부용) 원형 분포 잠재 좌표 생성
  Map<int, _LatentPoint> _generateCircularLatentPoints(math.Random random) {
    if (circularDoubleRing) {
      return _generateDoubleRingLatentPoints(random);
    }
    const radius = 1.2;
    final points = <int, _LatentPoint>{};
    for (int i = 0; i < numOfNodes; i++) {
      final angle =
          (2 * math.pi) * (i / numOfNodes) + random.nextDouble() * 0.15;
      final jitter = 0.08 * (random.nextDouble() - 0.5);
      final r = radius + jitter;
      final p = Offset(r * math.cos(angle), r * math.sin(angle));
      points[i] = _LatentPoint(clusterId: 0, point: p);
    }
    return points;
  }

  /// 이중 링: 안쪽·바깥쪽 링에 노드 분포 (더 균형 잡힌 시각)
  Map<int, _LatentPoint> _generateDoubleRingLatentPoints(math.Random random) {
    final points = <int, _LatentPoint>{};
    const innerRadius = 0.9;
    const outerRadius = 1.35;
    final half = numOfNodes ~/ 2;
    for (int i = 0; i < numOfNodes; i++) {
      final onInner = i < half;
      final n = onInner ? half : (numOfNodes - half);
      final idx = onInner ? i : (i - half);
      final angle = (2 * math.pi) * (idx / n) + random.nextDouble() * 0.2;
      final baseR = onInner ? innerRadius : outerRadius;
      final jitter = 0.06 * (random.nextDouble() - 0.5);
      final r = baseR + jitter;
      final p = Offset(r * math.cos(angle), r * math.sin(angle));
      points[i] = _LatentPoint(clusterId: 0, point: p);
    }
    return points;
  }

  /// (내부용) 클러스터 기반 잠재 좌표 생성
  /// - positions는 layout 초기 seed로도 사용되어 “비슷한 건 가까이”가 자연스럽게 나옴
  Map<int, _LatentPoint> _generateLatentPoints(math.Random random) {
    final c =
        clusterCount ??
        math.max(3, math.min(12, (math.sqrt(numOfNodes / 8)).round()));

    // 클러스터 센터 생성
    final centers = List.generate(c, (i) {
      final angle = (2 * math.pi) * (i / c);
      final radius = 1.0 + random.nextDouble() * 0.3;
      return Offset(radius * math.cos(angle), radius * math.sin(angle));
    });

    final points = <int, _LatentPoint>{};
    for (int i = 0; i < numOfNodes; i++) {
      final cid = random.nextInt(c);
      final center = centers[cid];
      final jitter = Offset(_gauss(random) * 0.18, _gauss(random) * 0.18);
      final p = center + jitter;
      points[i] = _LatentPoint(clusterId: cid, point: p);
    }
    return points;
  }

  bool _isAnchorIndex(int index) {
    if (minAnchors <= 0 || numOfNodes == 0) return false;
    final step = numOfNodes / minAnchors;
    for (int i = 0; i < minAnchors; i++) {
      final anchorIdx = (i * step).floor().clamp(0, numOfNodes - 1);
      if (index == anchorIdx) return true;
    }
    return false;
  }

  double _gauss(math.Random r) {
    // Box–Muller
    final u1 = (r.nextDouble()).clamp(1e-9, 1.0);
    final u2 = r.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  List<GraphNode> _generateNodes(
    math.Random random,
    Map<int, _LatentPoint> latent,
  ) {
    return List.generate(numOfNodes, (index) {
      final lp = latent[index]!;
      final position = Offset(
        (lp.point.dx + 2.0) * 120,
        (lp.point.dy + 2.0) * 120,
      );
      final isPublic = random.nextBool();
      final isAnchor =
          minAnchors > 0
              ? _isAnchorIndex(index)
              : (index % 7 == 0); // 클러스터 대표격으로 일부를 앵커로

      return GraphNode(
        id: index,
        label: 'Node $index',
        position: position,
        isPublic: isPublic,
        isAnchor: isAnchor,
        layoutHint: Offset(
          (lp.point.dx + 2.0) / 4 - 0.5,
          (lp.point.dy + 2.0) / 4 - 0.5,
        ),
        createdAt: DateTime.now().subtract(Duration(days: index)),
      );
    });
  }

  /// 엣지 생성 (핵심: 각 노드당 “비슷한 노드 k개”만 연결하는 sparse graph)
  /// - 거미줄 방지: O(N*k) 수준의 엣지 수로 강제됨
  /// - 유사도는 latent 공간 거리로 계산 (테스트용, 클라이언트에 임베딩 노출 X)
  List<GraphEdge> _generateSparseEdges(
    math.Random random,
    List<GraphNode> nodes,
    Map<int, _LatentPoint> latent,
  ) {
    final edges = <GraphEdge>[];
    final edgeKeys = <String>{};

    // 클러스터별로 묶어서 “같은 클러스터 내”에서만 후보 비교 (스케일 대응)
    final byCluster = <int, List<GraphNode>>{};
    for (final n in nodes) {
      final cid = latent[n.id]!.clusterId;
      byCluster.putIfAbsent(cid, () => []).add(n);
    }

    for (final n in nodes) {
      final cid = latent[n.id]!.clusterId;
      final candidates = byCluster[cid] ?? nodes;
      final p = latent[n.id]!.point;

      // 같은 클러스터 내에서 similarity topK 선택
      final scored = <(GraphNode, double)>[];
      for (final m in candidates) {
        if (m.id == n.id) continue;
        final q = latent[m.id]!.point;
        final sim = _similarityFromDistance((p - q).distance);
        if (sim >= minSimilarity) {
          scored.add((m, sim));
        }
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      final takeK = math.min(kNeighbors, scored.length);
      for (int i = 0; i < takeK; i++) {
        final m = scored[i].$1;
        final sim = scored[i].$2;
        _addUndirectedEdge(edges, edgeKeys, n.id, m.id, sim);
      }

      // 아주 소량의 cross-cluster 링크 (그래프가 완전 분리되는 것 방지)
      if (crossClusterRate > 0 && random.nextDouble() < crossClusterRate) {
        final other = nodes[random.nextInt(nodes.length)];
        if (latent[other.id]!.clusterId != cid) {
          final sim = 0.35 + random.nextDouble() * 0.15; // 낮은 유사도
          if (sim >= minSimilarity) {
            _addUndirectedEdge(edges, edgeKeys, n.id, other.id, sim);
          }
        }
      }
    }

    return edges;
  }

  double _similarityFromDistance(double d) {
    // 거리→유사도: 가까울수록 1.0
    // (exp가 예쁘게 떨어짐)
    final sigma = 0.35;
    final v = math.exp(-(d * d) / (2 * sigma * sigma));
    return v.clamp(0.0, 1.0);
  }

  void _addUndirectedEdge(
    List<GraphEdge> edges,
    Set<String> keys,
    int a,
    int b,
    double sim,
  ) {
    final from = a <= b ? a : b;
    final to = a <= b ? b : a;
    final key = '$from->$to';
    if (keys.contains(key)) return;
    keys.add(key);
    edges.add(
      GraphEdge(
        fromNodeId: from,
        toNodeId: to,
        similarity: sim,
        type: EdgeType.semantic,
      ),
    );
  }

  /// 특정 개수의 노드로 GraphData 생성 (편의 메서드)
  static GraphData generateWithNodeCount(int count) {
    final testData = TestData(numOfNodes: count);
    return testData.generateGraphData();
  }
}

class _LatentPoint {
  final int clusterId;
  final Offset point;
  const _LatentPoint({required this.clusterId, required this.point});
}
