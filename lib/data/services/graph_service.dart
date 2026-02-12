import 'package:dio/dio.dart';
import 'package:doppy/data/models/graph_search_models.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:doppy/graph/models/edge.dart';
import 'package:flutter/foundation.dart';

/// 그래프 API 서비스 (GET /api/graph, GET /api/graph/search)
/// Authorization: Bearer 필수
class GraphService {
  final Dio _dio = BaseApiService().dio;

  /// GET /api/graph?mode=mock|real&count=1~300(mock만)
  Future<GraphData> getGraph({String mode = 'real', int? count}) async {
    final query = <String, String>{'mode': mode};
    if (mode == 'mock' && count != null) {
      query['count'] = count.clamp(1, 300).toString();
    }
    final q = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final res = await _dio.get<Map<String, dynamic>>('/api/graph?$q');
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('그래프 로드 실패: ${res.statusCode}');
    }
    final data = res.data!;
    final nodesRaw = data['nodes'] as List<dynamic>? ?? [];
    final edgesRaw = data['edges'] as List<dynamic>? ?? [];
    final graph = GraphData(
      nodes: nodesRaw.map((e) => GraphNode.fromJson(e as Map<String, dynamic>)).toList(),
      edges: edgesRaw.map((e) => GraphEdge.fromJson(e as Map<String, dynamic>)).toList(),
    );
    if (kDebugMode) {
      final ids = graph.nodes.map((n) => n.id).toSet();
      final idStr = ids.length <= 30 ? ids.toString() : '${ids.take(15).toList()}...외 ${ids.length - 15}개';
      debugPrint('[GraphService] 로드 완료: nodes=${graph.nodes.length}, edges=${graph.edges.length}, nodeIds=$idStr');
    }
    return graph;
  }

  /// GET /api/graph/search
  /// mock=true: 서버 mock 데이터에서 랜덤 반환(테스트용). mock=false: q 필수, 실제 시맨틱 검색.
  Future<SearchResult> search(
    String query, {
    int limit = 30,
    bool useEmbedding = true,
    bool mock = true,
  }) async {
    final trimmed = query.trim();
    if (!mock && trimmed.isEmpty) {
      return SearchResult(nodeIds: {}, query: query);
    }

    final params = <String, dynamic>{
      'limit': limit.clamp(1, 100),
      'useEmbedding': useEmbedding,
      'mock': mock,
    };
    if (trimmed.isNotEmpty) params['q'] = trimmed;

    final res = await _dio.get<List<dynamic>>(
      '/api/graph/search',
      queryParameters: params,
    );

    if (res.statusCode != 200 || res.data == null) {
      throw Exception('검색 실패: ${res.statusCode}');
    }

    final list = res.data!;
    final hits = <GraphSearchHit>[];
    final nodeIds = <int>{};

    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final type = (item['type'] as String?) ?? 'post';
      final id = _parseId(item['id']);
      final label = (item['label'] as String?) ?? '';
      final score = (item['score'] as num?)?.toDouble() ?? 0.0;
      final createdAtStr = item['createdAt'] as String?;
      hits.add(GraphSearchHit(
        type: type,
        id: id,
        label: label,
        score: score,
        createdAt: createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
        isPublic: item['isPublic'] as bool?,
        conceptType: item['conceptType'] as String?,
      ));
      nodeIds.add(id);
    }

    if (kDebugMode) {
      debugPrint('[GraphService] 검색 완료: mock=$mock, q="$trimmed", hits=${hits.length}, nodeIds=$nodeIds');
    }
    return SearchResult(nodeIds: nodeIds, query: query, hits: hits);
  }

  static int _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
