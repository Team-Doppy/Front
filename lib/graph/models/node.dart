import 'dart:ui';

/// 노드 모델
class GraphNode {
  final int id;
  final String label;
  final bool isPublic;
  Offset position; // mutable - 레이아웃 알고리즘이 수정

  /// 서버: 개념/감정 군집 대표 여부
  final bool isAnchor;

  /// 서버 position 힌트 (x, y ∈ [-1, 1]). 레이아웃 초기 시드로 사용
  final Offset? layoutHint;

  /// 클러스터 ID (같은 c끼리 한 개념/군집). API: "c"
  final int? clusterId;
  /// 이 노드가 묶이는 앵커 포스트 ID. API: "a"
  final int? anchorId;
  /// 클러스터 내 순서. API: "orderInCluster"
  final int? orderInCluster;
  /// 삶 영향도 1~3. API: "intensity"
  final int? intensity;

  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  GraphNode({
    required this.id,
    required this.label,
    required this.position,
    required this.isPublic,
    this.isAnchor = false,
    this.layoutHint,
    this.clusterId,
    this.anchorId,
    this.orderInCluster,
    this.intensity,
    this.metadata,
    this.createdAt,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json['id']);
    final createdAtStr = json['createdAt'] as String?;
    return GraphNode(
      id: id,
      label: (json['label'] as String?) ?? '',
      position: Offset.zero,
      isPublic: (json['isPublic'] as bool?) ?? true,
      isAnchor: (json['isAnchor'] as bool?) ?? false,
      layoutHint: null,
      clusterId: _parseIdNullable(json['c']),
      anchorId: _parseIdNullable(json['a']),
      orderInCluster: _parseIdNullable(json['orderInCluster']),
      intensity: _parseInt1To3(json['intensity']),
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
    );
  }

  static int? _parseIdNullable(dynamic v) {
    if (v == null) return null;
    return _parseId(v);
  }

  static int? _parseInt1To3(dynamic v) {
    if (v == null) return null;
    if (v is int) return v.clamp(1, 3);
    if (v is num) return v.toInt().clamp(1, 3);
    return null;
  }

  static int _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  GraphNode copyWith({
    int? id,
    String? label,
    Offset? position,
    bool? isPublic,
    bool? isAnchor,
    Offset? layoutHint,
    int? clusterId,
    int? anchorId,
    int? orderInCluster,
    int? intensity,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) {
    return GraphNode(
      id: id ?? this.id,
      label: label ?? this.label,
      position: position ?? this.position,
      isPublic: isPublic ?? this.isPublic,
      isAnchor: isAnchor ?? this.isAnchor,
      layoutHint: layoutHint ?? this.layoutHint,
      clusterId: clusterId ?? this.clusterId,
      anchorId: anchorId ?? this.anchorId,
      orderInCluster: orderInCluster ?? this.orderInCluster,
      intensity: intensity ?? this.intensity,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
