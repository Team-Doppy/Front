import 'package:doppy/graph/models/node.dart';

/// 엣지 모델 (서버 스키마 준수)
/// conceptKeywords: 개념(contextual) 엣지 시 "연결 이유" 표시용, 감정/임베딩 엣지는 []
class GraphEdge {
  final int fromNodeId;
  final int toNodeId;
  final double similarity; // 0.0 ~ 1.0 (서버에서 계산)
  final EdgeType type;
  /// 개념 엣지: [개념 라벨, 앵커 쪽 키워드…, 타겟 쪽 키워드…]. 감정/임베딩: []
  final List<String> conceptKeywords;

  GraphEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.similarity,
    this.type = EdgeType.semantic,
    this.conceptKeywords = const [],
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'semantic';
    final keywordsRaw = json['conceptKeywords'];
    final List<String> conceptKeywords = keywordsRaw is List<dynamic>
        ? keywordsRaw
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    return GraphEdge(
      fromNodeId: _parseId(json['fromNodeId']),
      toNodeId: _parseId(json['toNodeId']),
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
      type: EdgeType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => EdgeType.semantic,
      ),
      conceptKeywords: conceptKeywords,
    );
  }

  static int _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

enum EdgeType { semantic, contextual, emotional }

/// 그래프 데이터 모델
class GraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  /// O(1) 노드 조회용 캐시 (첫 접근 시 한 번만 빌드)
  late final Map<int, GraphNode> _nodeById =
      {for (final n in nodes) n.id: n};

  GraphData({required this.nodes, required this.edges});

  factory GraphData.fromJson(Map<String, dynamic> json) {
    final nodesRaw = json['nodes'] as List<dynamic>? ?? [];
    final edgesRaw = json['edges'] as List<dynamic>? ?? [];
    return GraphData(
      nodes:
          nodesRaw
              .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
              .toList(),
      edges:
          edgesRaw
              .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  GraphNode? getNodeById(int id) => _nodeById[id];

  List<GraphEdge> getEdgesForNode(int nodeId) {
    return edges
        .where((edge) => edge.fromNodeId == nodeId || edge.toNodeId == nodeId)
        .toList();
  }

  List<GraphEdge> getEdgesBySimilarity(double threshold) {
    return edges.where((edge) => edge.similarity >= threshold).toList();
  }

  int getConnectionCount(int nodeId) {
    return getEdgesForNode(nodeId).length;
  }
}
