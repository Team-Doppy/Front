import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/graph_service.dart';
import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:doppy/graph/utils/node_count_utils.dart';

/// 검색 단계
enum SearchPhase {
  idle,
  searching,
  searchResult,
}

/// 그래프 + 검색 상태. 스플래시에서 그래프 로드, 홈에서 그래프·검색 UI 사용
class GraphProvider extends ChangeNotifier {
  static final GraphProvider _instance = GraphProvider._internal();
  factory GraphProvider() => _instance;
  GraphProvider._internal();

  final GraphService _graphService = GraphService();

  GraphData? _graph;
  bool _loading = false;
  String? _error;

  GraphData? get graph => _graph;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasGraph => _graph != null && _graph!.nodes.isNotEmpty;

  // 검색 상태 (기존 SearchProvider 통합)
  SearchPhase _searchPhase = SearchPhase.idle;
  String? _searchQuery;
  Set<int> _resultNodeIds = {};
  bool _isSearchFieldOpen = false;

  SearchPhase get searchPhase => _searchPhase;
  String? get searchQuery => _searchQuery;
  Set<int> get resultNodeIds => _resultNodeIds;
  bool get isSearchFieldOpen => _isSearchFieldOpen;

  /// GET /api/graph 호출 후 그래프 저장. 실패 시 _graph는 null, _error 설정
  Future<void> loadGraph({String mode = 'real', int? count}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _graph = await _graphService.getGraph(mode: mode, count: count);
    } catch (e) {
      _graph = null;
      _error = e.toString();
      if (kDebugMode) debugPrint('[GraphProvider] loadGraph 실패: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _graph = null;
    _error = null;
    _searchPhase = SearchPhase.idle;
    _searchQuery = null;
    _resultNodeIds = {};
    _isSearchFieldOpen = false;
    notifyListeners();
  }

  // --- 검색 (기존 SearchProvider) ---

  void openSearchField() {
    _isSearchFieldOpen = true;
    notifyListeners();
  }

  void closeToNormal() {
    _isSearchFieldOpen = false;
    _searchPhase = SearchPhase.idle;
    _searchQuery = null;
    _resultNodeIds = {};
    notifyListeners();
  }

  void closeSearchField() {
    _isSearchFieldOpen = false;
    notifyListeners();
  }

  Future<void> submitSearch(String query) async {
    _isSearchFieldOpen = false;
    _searchPhase = SearchPhase.searching;
    _searchQuery = query;
    _resultNodeIds = {};
    notifyListeners();

    try {
      final result = await _graphService.search(query);
      if (_searchPhase != SearchPhase.searching) return;
      _searchPhase = SearchPhase.searchResult;
      _resultNodeIds = result.nodeIds;
      if (kDebugMode) {
        debugPrint('[GraphProvider] submitSearch 완료: resultNodeIds=$_resultNodeIds (${_resultNodeIds.length}개)');
      }
    } catch (e) {
      if (_searchPhase == SearchPhase.searching) {
        _searchPhase = SearchPhase.idle;
        _resultNodeIds = {};
      }
    }
    notifyListeners();
  }

  void enterSearchMode() {
    _isSearchFieldOpen = true;
    notifyListeners();
  }

  void leaveSearchMode() {
    _isSearchFieldOpen = false;
    notifyListeners();
  }

  // --- LOD: 확대 단계에 따라 보여줄 노드 ID (뷰에서 zoom/minScale 전달) ---

  /// 확대 단계(zoom/minScale)에 따라 보여줄 노드 ID. null이면 전체 표시.
  /// 70개 초과 시: 엣지 연결 노드 우선(degree→최신순), 남는 슬롯은 최신순.
  static Set<int>? getVisibleNodeIdsForZoom({
    required GraphData graph,
    required double zoom,
    required double minScale,
    int? selectedNodeId,
  }) {
    final n = graph.nodes.length;
    if (n <= NodeCountUtils.lodThreshold) return null;

    final ratio = (zoom / (minScale <= 0 ? 1.0 : minScale)).clamp(0.1, 10.0);
    final maxNodes =
        ratio <= 1.15
            ? NodeCountUtils.lodThreshold
            : _clamp(
              (NodeCountUtils.lodThreshold * math.pow(ratio, 1.8)).round(),
              NodeCountUtils.lodThreshold,
              n,
            );

    return _computeLodNodeSet(
      graph: graph,
      maxNodes: maxNodes,
      selectedNodeId: selectedNodeId,
    );
  }

  /// 초기 fit용 시드 노드 ID (LOD 시 bounds 계산)
  static Set<int> getSeedNodeIdsForFit({
    required GraphData graph,
    required int maxNodes,
    int? selectedNodeId,
  }) {
    return _computeLodNodeSet(
      graph: graph,
      maxNodes: maxNodes,
      selectedNodeId: selectedNodeId,
    );
  }

  static int _clamp(int raw, int lo, int hi) {
    if (raw < lo) return lo;
    if (raw > hi) return hi;
    return raw;
  }

  static Set<int> _computeLodNodeSet({
    required GraphData graph,
    required int maxNodes,
    int? selectedNodeId,
  }) {
    final edgeIds = <int>{};
    final degree = <int, int>{};
    for (final e in graph.edges) {
      degree[e.fromNodeId] = (degree[e.fromNodeId] ?? 0) + 1;
      degree[e.toNodeId] = (degree[e.toNodeId] ?? 0) + 1;
      if (graph.getNodeById(e.fromNodeId) != null) edgeIds.add(e.fromNodeId);
      if (graph.getNodeById(e.toNodeId) != null) edgeIds.add(e.toNodeId);
    }

    final edgeNodes = <GraphNode>[];
    for (final id in edgeIds) {
      final node = graph.getNodeById(id);
      if (node != null) edgeNodes.add(node);
    }
    edgeNodes.sort((a, b) {
      final da = degree[a.id] ?? 0;
      final db = degree[b.id] ?? 0;
      if (db != da) return db.compareTo(da);
      final at = a.createdAt ?? DateTime(0);
      final bt = b.createdAt ?? DateTime(0);
      return bt.compareTo(at);
    });

    final out = <int>{};
    for (final node in edgeNodes) {
      if (out.length >= maxNodes) break;
      out.add(node.id);
    }
    if (selectedNodeId != null && out.length < maxNodes) out.add(selectedNodeId);

    final byNewest = [...graph.nodes]
      ..sort((a, b) {
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });
    for (final node in byNewest) {
      if (out.length >= maxNodes) break;
      if (!out.contains(node.id)) out.add(node.id);
    }
    return out;
  }
}
