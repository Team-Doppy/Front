/// 검색 결과 한 건 (포스트 또는 개념)
class GraphSearchHit {
  final String type; // 'post' | 'concept'
  final int id;
  final String label;
  final double score;
  final DateTime? createdAt;
  final bool? isPublic;
  final String? conceptType;

  const GraphSearchHit({
    required this.type,
    required this.id,
    required this.label,
    required this.score,
    this.createdAt,
    this.isPublic,
    this.conceptType,
  });
}

/// 검색 결과 모델
class SearchResult {
  final Set<int> nodeIds;
  final String query;
  final List<GraphSearchHit> hits;

  const SearchResult({
    required this.nodeIds,
    required this.query,
    this.hits = const [],
  });
}
